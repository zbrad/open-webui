#!/usr/bin/env python3
"""smoke_test.py -- verify a real, running open-webui instance end-to-end,
without a human at a browser.

Drives an actual headless Chromium (via Playwright) against a live
instance (e.g. one started via deploy/local/run-local.sh against a scratch
DATA_DIR), the same pattern proven on the ComfyUI fork's
test_workflow_headless.py: navigate to the real app, use the app's own
auth/API surface to get in rather than fighting a login form, and check
provider-agnostic invariants that should hold regardless of which model
backend (Ollama, llama.cpp, anything else) is actually configured.

Deliberately provider-agnostic: it asserts "at least one model is listed"
and "a chat completion round-trip against whatever model is first in that
list returns real content" rather than hardcoding a model id, so the exact
same suite is meant to be re-run unmodified before and after a change
(Ollama removal, a Python/dependency bump, etc.) -- a failure after such a
change is then a real regression signal, not a stale assumption about which
provider happens to be configured.

Auth: signs in via POST /api/v1/auths/signin (plain HTTP, not the login
form) to get a JWT, then injects it into the browser context's localStorage
before any page loads (matching how the frontend itself stores it --
`localStorage.token = <jwt>`, see src/routes/auth/+page.svelte). Requires
an admin account to already exist -- either run deploy/local/setup.sh
first, or start run-local.sh with WEBUI_ADMIN_EMAIL/WEBUI_ADMIN_PASSWORD
set (bootstraps the first admin on startup).

Requires: `pip install playwright && playwright install chromium`
(no --with-deps needed if the host already has the usual browser shared
libs, which avoids needing sudo).

Usage:
    smoke_test.py [--url http://127.0.0.1:8322] [--admin-email EMAIL]
        [--admin-password PASSWORD] [--timeout SECONDS] [--out FILE]

Exit code 0 on success, 1 on any failure. Structured JSON result printed to
stdout (also written to --out if given); progress goes to stderr.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request

from playwright.sync_api import sync_playwright

# Routes that must render without throwing, regardless of which model
# provider is configured -- these are the actual regression net, not the
# chat round-trip below (which depends on a real model being reachable).
CHECKED_ROUTES = ['/', '/admin/settings/connections', '/admin/settings/models']


def _log(*args: object) -> None:
    print(*args, file=sys.stderr)


def http_json(
    url: str,
    data: dict | None = None,
    token: str | None = None,
    method: str | None = None,
    timeout: float = 15,
) -> dict:
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    body = json.dumps(data).encode('utf-8') if data is not None else None
    request = urllib.request.Request(
        url, data=body, headers=headers, method=method or ('POST' if data is not None else 'GET')
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


def run(base_url: str, admin_email: str, admin_password: str, timeout: float = 60) -> dict:
    """Run the full smoke suite against `base_url`.

    Returns a structured result, always with a `success` bool and a
    `stage` naming where it stopped if not:
        {"success": False, "stage": "signin", "error": "..."}
        {"success": False, "stage": "load:<route>", "error": "..."}
        {"success": False, "stage": "console_errors", "route": "...", "errors": [...]}
        {"success": False, "stage": "chat_ui_not_rendered", "error": "..."}
        {"success": False, "stage": "list_models", "error": "..."}
        {"success": False, "stage": "chat_completion", "error": "..."}
        {"success": True, "checks": {...}}
    """
    base_url = base_url.rstrip('/')

    _log(f'[+] signing in as {admin_email} ...')
    try:
        session = http_json(f'{base_url}/api/v1/auths/signin', {'email': admin_email, 'password': admin_password})
    except (urllib.error.URLError, urllib.error.HTTPError) as e:
        return {'success': False, 'stage': 'signin', 'error': str(e)}
    token = session.get('token')
    if not token:
        return {'success': False, 'stage': 'signin', 'error': 'no token in signin response'}
    _log('[+] signed in')

    checks: dict = {}
    console_errors: dict[str, list[str]] = {}

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        # Inject the token the same way the app itself would after a real
        # login (localStorage.token = <jwt>) -- runs before every
        # navigation in this context, so no page ever sees a logged-out
        # state and no login-form selectors are needed.
        context.add_init_script(f'window.localStorage.setItem("token", {json.dumps(token)});')

        for route in CHECKED_ROUTES:
            page = context.new_page()
            errors: list[str] = []
            page.on('console', lambda msg, e=errors: e.append(msg.text) if msg.type == 'error' else None)
            page.on('pageerror', lambda exc, e=errors: e.append(str(exc)))

            _log(f'[+] loading {route} ...')
            try:
                page.goto(f'{base_url}{route}', wait_until='networkidle', timeout=30000)
                if route == '/':
                    # Confirm the actual chat UI rendered, not just an
                    # empty/blank SPA shell that happened to go networkidle.
                    page.wait_for_selector('#chat-input', timeout=15000)
            except Exception as e:
                page.close()
                browser.close()
                stage = 'chat_ui_not_rendered' if route == '/' else f'load:{route}'
                return {'success': False, 'stage': stage, 'error': str(e)}

            console_errors[route] = list(errors)
            page.close()

        browser.close()

    for route, errors in console_errors.items():
        if errors:
            return {'success': False, 'stage': 'console_errors', 'route': route, 'errors': errors}
    checks['pages_loaded'] = CHECKED_ROUTES
    _log('[+] all checked routes loaded clean (no console errors, chat UI rendered)')

    _log('[+] listing models via GET /api/models ...')
    try:
        models = http_json(f'{base_url}/api/models', token=token, method='GET')
    except (urllib.error.URLError, urllib.error.HTTPError) as e:
        return {'success': False, 'stage': 'list_models', 'error': str(e)}
    model_list = models.get('data', [])
    if not model_list:
        return {'success': False, 'stage': 'list_models', 'error': 'no models returned', 'raw': models}
    model_id = model_list[0]['id']
    checks['model_count'] = len(model_list)
    checks['model_id'] = model_id
    _log(f'[+] {len(model_list)} model(s) listed, testing with {model_id!r}')

    _log('[+] chat completion round-trip ...')
    try:
        completion = http_json(
            f'{base_url}/api/chat/completions',
            {
                'model': model_id,
                'messages': [{'role': 'user', 'content': 'Reply with exactly one word: PONG'}],
                'stream': False,
            },
            token=token,
            timeout=timeout,
        )
    except (urllib.error.URLError, urllib.error.HTTPError) as e:
        return {'success': False, 'stage': 'chat_completion', 'error': str(e)}

    content = completion.get('choices', [{}])[0].get('message', {}).get('content', '')
    if not content.strip():
        return {'success': False, 'stage': 'chat_completion', 'error': 'empty response content', 'raw': completion}
    checks['chat_response'] = content[:200]
    _log(f'[✓] chat completion returned: {content[:200]!r}')

    return {'success': True, 'checks': checks}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--url', default='http://127.0.0.1:8322')
    ap.add_argument('--admin-email', required=True)
    ap.add_argument('--admin-password', required=True)
    ap.add_argument('--timeout', type=float, default=60)
    ap.add_argument('--out', default=None, help='also write the JSON result to this file')
    args = ap.parse_args()

    result = run(args.url, args.admin_email, args.admin_password, args.timeout)

    output = json.dumps(result, indent=2)
    print(output)
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            f.write(output)

    return 0 if result['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

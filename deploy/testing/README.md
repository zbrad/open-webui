# Browser smoke test

`smoke_test.py` drives a real headless Chromium (via Playwright) against a
running open-webui instance and checks a handful of provider-agnostic
invariants: the admin connections/models settings pages and the main chat
page all render without a console error, the model list is non-empty, and
a real chat completion round-trip against whatever model is first in that
list returns actual content.

It's deliberately provider-agnostic (no Ollama- or llama.cpp-specific
assertions) so the exact same suite can be run unmodified before and after
a change — a failure afterward is then a real regression signal, not a
stale assumption about which model backend happens to be configured. This
mirrors the pattern already proven on the ComfyUI fork's
`test_workflow_headless.py`: drive the real app via its own API/auth
surface rather than reimplementing frontend logic or fighting brittle DOM
selectors, and prefer this over Cypress (removed upstream, would be a
from-scratch rebuild here) or the Claude-in-Chrome extension (requires a
real desktop Chrome instance with the extension installed — can't run
headless on a shared dev box, already ruled out for the same reason during
the ComfyUI work).

## Setup

```bash
pip install -r deploy/testing/requirements.txt
playwright install chromium
```

## Usage

1. Start a real instance against a scratch `DATA_DIR` (don't point this at
   real production data — this test creates a chat and calls a real model):

   ```bash
   DATA_DIR=/tmp/owui-smoke/data HOST=127.0.0.1 PORT=8322 \
       WEBUI_ADMIN_EMAIL=smoke@example.com \
       WEBUI_ADMIN_PASSWORD=smoke-test-password \
       deploy/local/run-local.sh &
   ```

   (`WEBUI_ADMIN_EMAIL`/`WEBUI_ADMIN_PASSWORD` bootstrap the first admin
   account on startup — see `deploy/local/run-local.sh`.)

2. Run the smoke test:

   ```bash
   python3 deploy/testing/smoke_test.py \
       --url http://127.0.0.1:8322 \
       --admin-email smoke@example.com \
       --admin-password smoke-test-password \
       --out deploy/testing/baseline_result.json
   ```

Exit code 0 on success, 1 on any failure — see the `stage` field in the
printed JSON for where it stopped. A model backend (e.g. a real llama.cpp
connection, configured the same way an admin would via `POST
/openai/config/update` or the Connections settings page) must already be
reachable from the instance for the chat completion check to have anything
to talk to.

## Gotchas hit while building this

- **Match `--url`'s host to `CORS_ALLOW_ORIGIN` exactly.** Browsers treat
  `localhost` and `127.0.0.1` as different origins even though they
  resolve to the same host — if the server's `CORS_ALLOW_ORIGIN` (set by
  `run-local.sh`, defaults to `http://localhost:${PORT}`) doesn't match
  the origin Playwright actually navigates to, the socket.io WebSocket
  handshake gets rejected (403) even though plain HTTP requests work fine.
  Use the same hostname for both, e.g. `HOST=127.0.0.1 CORS_ALLOW_ORIGIN=http://localhost:$PORT`
  paired with `--url http://localhost:$PORT` (not `127.0.0.1`), or set
  `CORS_ALLOW_ORIGIN` to match whichever host you actually pass to `--url`.
- **A stale `build/` directory produces confusing, unrelated-looking
  console errors** — it's gitignored, so it silently survives a branch
  switch. If you see a console error referencing something that doesn't
  exist in the current source tree at all, rebuild first (`npm ci &&
  NODE_OPTIONS=--max-old-space-size=8192 npm run build` — see
  `deploy/README.md`) before assuming it's a real bug.

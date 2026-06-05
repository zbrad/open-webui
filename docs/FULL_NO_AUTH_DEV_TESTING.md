# Full No-Auth Dev Mode: Testing and Verification

This document defines a safe developer-only full no-auth mode and provides a repeatable verification checklist.

## Purpose

Use full no-auth mode only for local development speed. This mode is intentionally insecure and must never be enabled for shared or production deployments.

## Proposed Contract

Use an explicit flag:

- FULL_NO_AUTH_DEV=true
- WEBUI_AUTH=false

Behavior when enabled:

1. Unauthenticated requests are bypassed only for loopback clients (127.0.0.1/::1/localhost).
2. Authenticated requests (API key/JWT) still use normal auth validation.
3. Non-loopback unauthenticated requests are rejected (403).
4. Startup fails closed when guardrails are not met.
5. A clear warning appears in logs and UI that auth is disabled.
6. Production mode rejects startup when full no-auth is enabled.

## Safety Guardrails

Required guardrails:

1. Host bind restriction:
- Unauthenticated bypass is loopback-only by request client IP.
- Authenticated requests are allowed and validated normally.

2. Environment restriction:
- Require explicit dev marker (for example ENV=dev).
- Refuse to start in production profile.

3. Auth mode coupling:
- FULL_NO_AUTH_DEV requires WEBUI_AUTH=false.

4. Optional URL guard:
- If WEBUI_URL is set, hostname must resolve to loopback (localhost/127.0.0.1/::1).

5. Visibility:
- Log warning at startup with mode and bind target.
- Show persistent UI banner.

6. Operator friction:
- Require explicit flag each start (no silent persistence).

## Verification Matrix

### A. Baseline (auth enabled)

Goal: confirm normal auth behavior before toggling no-auth mode.

1. Ensure FULL_NO_AUTH_DEV is unset or false.
2. Restart Open WebUI.
3. Call chat completions without Authorization header.

Expected:
- Request is rejected with auth error (401/403 depending on route behavior).

### B. Enable full no-auth mode

1. Set FULL_NO_AUTH_DEV=true.
2. Set WEBUI_AUTH=false.
3. Ensure ENV=dev.
4. If WEBUI_URL is set, ensure it uses localhost/127.0.0.1/::1.
5. Restart Open WebUI.

Expected:
- Startup succeeds.
- Logs contain explicit insecure mode warning.
- UI shows a visible no-auth warning banner.

### C. Positive functional tests (no key, no token)

Run with no Authorization header.

1. Health:

curl -sS http://localhost:8080/health

Expected:
- Success response.

2. Models list:

curl -sS http://localhost:8080/api/v1/models

Expected:
- Model list is returned.

3. Chat completions:

curl -sS -X POST http://localhost:8080/api/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nemotron-3-nano:latest",
    "messages": [{"role": "user", "content": "reply with NO_AUTH_DEV_OK"}],
    "stream": false
  }'

Expected:
- 200 response.
- Assistant content includes NO_AUTH_DEV_OK.

### D. VS Code custom endpoint test (no key)

Use endpoint:

- URL: http://your-host:8080/api/chat/completions
- API type: chat-completions
- No API key configured for this temporary local test path.

Expected:
- Prompt round-trip succeeds only when VS Code reaches Open WebUI via loopback.
- If VS Code is remote/non-loopback, request is rejected with 403.
- No 401 responses in Open WebUI logs for this request flow.

### E. Non-local authenticated test (API key)

Goal: confirm remote clients can still authenticate while anonymous remote requests are blocked.

1. Generate API key (localhost session):

curl -sS -X POST http://localhost:8080/api/v1/auths/api_key

2. Call models endpoint from non-loopback host/IP using Authorization header:

curl -sS -H "Authorization: Bearer sk-<real_key>" http://<host-ip>:8080/api/v1/models

Expected:
- 200 response with model list.

3. Call same endpoint from non-loopback without auth header.

Expected:
- 403 response with message indicating only unauthenticated loopback clients are allowed.

## How External Callers Get an API Key

Use this flow when the client is not on loopback and must authenticate.

### 1) Ensure API keys are enabled

Check admin config:

curl -sS http://localhost:8080/api/v1/auths/admin/config

Required values:

- ENABLE_API_KEYS: true
- ENABLE_API_KEYS_ENDPOINT_RESTRICTIONS: false (or configure allowed paths to include your target endpoints)

### 2) Generate a key

From a trusted local admin session:

curl -sS -X POST http://localhost:8080/api/v1/auths/api_key

Response contains:

- api_key: sk-...

### 3) Call chat API from external client

Use Bearer auth against the chat endpoint:

curl -sS -X POST http://<host-ip>:8080/api/chat/completions \
  -H "Authorization: Bearer sk-<real_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nemotron-3-nano:latest",
    "messages": [{"role": "user", "content": "reply with EXTERNAL_KEY_OK"}],
    "stream": false
  }'

Expected:

- 200 response and model output.

### 4) Troubleshooting

- 403 with FULL_NO_AUTH_DEV only accepts unauthenticated loopback clients:
  no key was provided (or header not forwarded by proxy/client).
- 401 token expired or invalid:
  key is stale/invalid, or client is still using an old cached secret.
- 403 API key not allowed:
  ENABLE_API_KEYS is false, permission is missing, or endpoint restrictions block path.

### F. Negative security tests (must fail)

These tests verify guardrails are active.

1. Non-loopback bind target:
- Start with FULL_NO_AUTH_DEV=true and bind 0.0.0.0.

Expected:
- Local requests still work, but non-loopback clients are rejected with 403.

2. Production profile:
- Start with FULL_NO_AUTH_DEV=true in production mode.

Expected:
- Startup fails closed with clear error.

3. WEBUI_AUTH still true:
- Start with FULL_NO_AUTH_DEV=true and WEBUI_AUTH=true.

Expected:
- Startup fails closed with clear error.

4. Guardrail log audit:

Expected:
- Logs contain mode warning, reason for any startup refusal, and bind details.

## GPU Verification (optional but recommended)

If validating model runtime path at the same time:

1. Run a completion request.
2. Check runtime processor status:

ollama ps

Expected:
- Target model shows GPU usage.

3. Check NVIDIA process usage:

nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv

Expected:
- llama-server appears with non-trivial GPU memory use during/after generation.

## Exit Criteria

Full no-auth dev mode is considered verified only if all are true:

1. Keyless local requests succeed for model testing paths.
2. Non-loopback unauthenticated requests are rejected.
3. Non-loopback authenticated requests work with valid credentials.
4. Startup fails closed when guardrails are violated.
5. Warnings are visible in logs and UI.
6. Baseline auth mode still works when FULL_NO_AUTH_DEV is disabled.

## Rollback

To return to normal security behavior:

1. Set FULL_NO_AUTH_DEV=false or unset it.
2. Restart Open WebUI.
3. Re-run Baseline checks from section A.

## Notes

- Prefer API keys for any shared host, remote access, tunneling, or long-running environment.
- This mode is for local developer velocity only.

---

Last updated: 2026-06-04

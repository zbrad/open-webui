# Build and Run (local / systemd)

Two deployment modes are covered here: **local** (venv, no Docker) and
**service** (systemd `--user`, no root needed). Docker deployment is
upstream's own `Makefile`/`docker-compose.yaml` at the repo root, unchanged
here — a fork-specific Docker build variant (CUDA/GPU images, launcher
script) is tracked separately and not part of this pass.

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | matches `pyproject.toml`'s `requires-python` (check before assuming — this has changed before) | Backend runtime |
| Node.js | matches `package.json`'s `engines.node` (check before assuming — same caveat) | Frontend build |
| npm | ≥ 6.0 | Frontend dependencies |
| An OpenAI-compatible server (llama.cpp, LMStudio, etc.) | any | LLM inference — configured as a connection, not bundled/managed by these scripts |

---

## Build

The frontend is compiled automatically when you install the Python package.
`pip install -e` triggers `hatch_build.py`, which runs `npm install` and `npm run build`,
placing the compiled assets into `backend/open_webui/static/`.

```bash
# Create the venv at the repo root
python3 -m venv .venv

# Install backend + build frontend (requires npm on PATH)
.venv/bin/pip install -e backend
```

To rebuild the frontend only (e.g. after a `git pull`):

```bash
.venv/bin/pip install -e backend --no-deps
# or force a full reinstall:
.venv/bin/pip install -e backend --force-reinstall
```

Or directly with npm (what the above does under the hood):

```bash
npm ci                                          # after any branch switch / package-lock.json change
NODE_OPTIONS=--max-old-space-size=8192 npm run build
```

Two gotchas hit repeatedly on this box, both silent otherwise:
- **`node_modules` doesn't follow a branch switch.** It's gitignored, so
  checking out a branch with a different `package-lock.json` leaves a
  mismatched `node_modules` in place — `npm run build` then fails fast on
  a missing/wrong-version package (or, worse, quietly builds against
  stale source if the mismatch doesn't happen to break resolution).
  Always `npm ci` after switching branches, not just once.
- **The production build needs a larger V8 heap than Node's default** on
  this machine — a plain `npm run build` dies partway through with
  `JavaScript heap out of memory` even though the box has memory free
  (the default old-space limit is fixed, not sized off available RAM).
  `NODE_OPTIONS=--max-old-space-size=8192` fixes it.
- Also confirm `node --version` satisfies `package.json`'s `engines.node`
  range first (`nvm use 22` if not — see `deploy/testing/README.md` for
  why this matters for the browser smoke test specifically).

---

## Configure

`deploy/local/setup.sh` is an interactive script that writes an env file for either mode.
Run it **before** starting for the first time, and again whenever you need to rotate keys
or change API settings. Re-running pre-fills all prompts from the existing file.

```bash
# Local mode — writes to <repo-root>/.env.local
deploy/local/setup.sh --mode local

# Service mode — writes to ~/.config/open-webui/env
deploy/local/setup.sh --mode service
```

Settings collected:

| Setting | Default | Notes |
|---------|---------|-------|
| `PORT` | `3000` | |
| `HOST` | `0.0.0.0` | |
| `UVICORN_WORKERS` | `1` | |
| `CORS_ALLOW_ORIGIN` | `*` (service) / `http://localhost:<PORT>` (local) | |
| `WEBUI_SECRET_KEY` | auto-generated | Signs all JWTs — changing it invalidates active sessions |
| `OPENAI_API_KEY` | _(optional)_ | Any OpenAI-compatible endpoint |
| `OPENAI_API_BASE_URL` | `https://api.openai.com/v1` | |
| `WEBUI_ADMIN_EMAIL/PASSWORD/NAME` | _(optional)_ | Bootstraps the first admin on first startup only |
| `WEBUI_DEFAULT_API_KEY` | auto-generated | Fixed API key for integrations — run `bootstrap-api-key.sh` after first start |

Keys not listed above that exist in the env file are preserved unchanged on re-run.

---

## Run — Local (venv)

Starts uvicorn directly from the repo `.venv`. Manages the secret key
automatically if `setup.sh` has not been run.

```bash
# Production mode
make local-start
# or directly:
deploy/local/run-local.sh

# Dev mode (--reload, wider CORS)
make local-dev
# or directly:
deploy/local/dev.sh
```

Override any setting inline:

```bash
PORT=8080 deploy/local/run-local.sh
```

---

## Run — Service (systemd `--user`)

No root required for day-to-day start/stop/restart. The one root step is
`loginctl enable-linger` (below), needed only so the service survives
logout/reboot; `deploy/service/deploy.sh` checks for it and prints the exact
command if missing rather than running it itself.

```bash
# 1. Configure
deploy/local/setup.sh --mode service

# 2. Install and enable the systemd --user unit
deploy/service/deploy.sh

# 3. Start
systemctl --user start open-webui

# 4. (Optional) Bootstrap the default API key for integrations
#    Wait ~5s for the admin user to be created on first startup, then:
deploy/service/bootstrap-api-key.sh
```

Useful commands:

```bash
make service-start      # systemctl --user start open-webui
make service-stop       # systemctl --user stop open-webui
make service-restart    # systemctl --user restart open-webui
make service-status     # systemctl --user status open-webui
make service-logs       # journalctl --user -u open-webui -f
```

To update config without reinstalling the unit:

```bash
deploy/local/setup.sh --mode service
systemctl --user restart open-webui
```

Survive logout/reboot (one-time, needs a real sudo prompt — run it yourself,
this isn't run for you):

```bash
sudo loginctl enable-linger $(id -un)
```

### Testing the API endpoint

After bootstrapping the default API key, test it:

```bash
# Get the API key from the env file
API_KEY=$(grep WEBUI_DEFAULT_API_KEY ~/.config/open-webui/env | cut -d= -f2)

# Test the models endpoint
curl http://localhost:8080/api/models \
  -H "Authorization: Bearer $API_KEY"

# Test chat completion
curl -X POST http://localhost:8080/api/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2:latest",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }'
```

---

## Make targets — quick reference

| Target | Description |
|--------|-------------|
| `local-setup` | `setup.sh --mode local` |
| `local-setup-service` | `setup.sh --mode service` |
| `local-start` | `run-local.sh` |
| `local-dev` | `dev.sh` (reload mode) |
| `service-install` | `deploy.sh` (install + enable the `--user` unit) |
| `service-start/stop/restart` | `systemctl --user` wrappers |
| `service-status` | `systemctl --user status open-webui` |
| `service-logs` | `journalctl --user -u open-webui -f` |

Docker targets (`install`, `start`, `stop`, `update`, ...) are upstream's
own, unchanged — see the root `Makefile`.

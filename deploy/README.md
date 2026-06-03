# Build and Run

Three deployment modes are supported: **local** (venv, no Docker), **service** (systemd), and **docker**.

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | ≥ 3.14.3 | Backend runtime |
| Node.js | 18.13 – 22.x | Frontend build (via `hatch_build.py`) |
| npm | ≥ 6.0 | Frontend dependencies |
| Ollama | any | LLM inference (local modes) |

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

---

## Configure

`deploy/local/setup.sh` is an interactive script that writes an env file for either mode.
Run it **before** starting for the first time, and again whenever you need to rotate keys
or change API settings. Re-running pre-fills all prompts from the existing file.

```bash
# Local mode — writes to <repo-root>/.env.local
deploy/local/setup.sh --mode local

# Service mode — writes to /etc/open-webui/env (auto-escalates to sudo)
deploy/local/setup.sh --mode service
```

Settings collected:

| Setting | Default | Notes |
|---------|---------|-------|
| `PORT` | `3000` | |
| `HOST` | `0.0.0.0` | |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | |
| `UVICORN_WORKERS` | `1` | |
| `CORS_ALLOW_ORIGIN` | `*` (service) / `http://localhost:<PORT>` (local) | |
| `WEBUI_SECRET_KEY` | auto-generated | Signs all JWTs — changing it invalidates active sessions |
| `OPENAI_API_KEY` | _(optional)_ | Any OpenAI-compatible endpoint |
| `OPENAI_API_BASE_URL` | `https://api.openai.com/v1` | |
| `WEBUI_ADMIN_EMAIL/PASSWORD/NAME` | _(optional)_ | Bootstraps the first admin on first startup only |

Keys not listed above that exist in the env file are preserved unchanged on re-run.

---

## Run — Local (venv)

Starts uvicorn directly from the repo `.venv`. Manages the Ollama process and secret key
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
PORT=8080 OLLAMA_BASE_URL=http://other-host:11434 deploy/local/run-local.sh
```

---

## Run — Service (systemd)

```bash
# 1. Configure
deploy/local/setup.sh --mode service

# 2. Install and enable the systemd unit (auto-escalates to sudo)
deploy/service/deploy.sh

# 3. Start
sudo systemctl start open-webui
```

Useful commands:

```bash
make service-start      # sudo systemctl start open-webui
make service-stop       # sudo systemctl stop open-webui
make service-restart    # sudo systemctl restart open-webui
make service-status     # systemctl status open-webui
make service-logs       # journalctl -u open-webui -f
```

To update config without reinstalling the unit:

```bash
deploy/local/setup.sh --mode service
sudo systemctl restart open-webui
```

---

## Run — Docker

### Quick start (Ollama + WebUI)

```bash
make docker-up           # docker compose up -d
make docker-up-build     # build image first, then up
make docker-stop
make docker-remove       # tear down + delete volumes
```

### Interactive launcher (GPU, ports, data mounts)

```bash
make docker-launch
# or:
deploy/docker/docker-compose-launcher.sh --enable-gpu[count=1] --webui[port=8080]
```

### Build CUDA images

```bash
# CUDA + upstream Ollama
deploy/docker/build-cuda-ollama.sh

# CUDA + local spark binary (requires ../ollama/ollama-server-spark)
deploy/docker/build-cuda-spark.sh
```

Environment variables for Docker builds:

```bash
CUDA_VER=cu133 IMAGE_TAG=my-tag deploy/docker/build-cuda-ollama.sh
```

---

## Make targets — quick reference

| Target | Description |
|--------|-------------|
| `local-setup` | `setup.sh --mode local` |
| `local-setup-service` | `setup.sh --mode service` |
| `local-start` | `run-local.sh` |
| `local-dev` | `dev.sh` (reload mode) |
| `service-install` | `deploy.sh` (install + enable unit) |
| `service-start/stop/restart` | `systemctl` wrappers |
| `service-status` | `systemctl status open-webui` |
| `service-logs` | `journalctl -u open-webui -f` |
| `docker-up` | `docker compose up -d` |
| `docker-up-build` | `docker compose up -d --build` |
| `docker-start/stop` | compose start/stop |
| `docker-remove` | tear down + delete volumes |
| `docker-update` | pull model updates, git pull, rebuild |
| `docker-launch` | interactive GPU/port launcher |

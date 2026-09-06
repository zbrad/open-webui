#!/usr/bin/env bash
# Run open-webui locally using the .venv Python install (no Docker).
# Expects: .venv built. ollama on PATH is optional -- if present and not
# already running, it's auto-started; if absent (e.g. serving models via
# llama.cpp instead), that step is skipped.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
VENV="${REPO_ROOT}/.venv"
PYTHON="${VENV}/bin/python"

# Source local env overrides if present (written by deploy/local/setup.sh)
ENV_LOCAL="${REPO_ROOT}/.env.local"
if [[ -f "${ENV_LOCAL}" ]]; then
    set -o allexport
    # shellcheck source=/dev/null
    source "${ENV_LOCAL}"
    set +o allexport
fi

PORT="${PORT:-3000}"
HOST="${HOST:-0.0.0.0}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
UVICORN_WORKERS="${UVICORN_WORKERS:-1}"
CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-http://localhost:${PORT}}"
USER_AGENT="${USER_AGENT:-open-webui}"
LOKY_MAX_CPU_COUNT="${LOKY_MAX_CPU_COUNT:-1}"
TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"

usage() {
    echo "Usage: [PORT=8080] [HOST=0.0.0.0] [OLLAMA_BASE_URL=http://localhost:11434] $0"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -x "${PYTHON}" ]]; then
    echo "ERROR: ${PYTHON} not found — run: python3 -m venv .venv && pip install -e backend" >&2
    exit 1
fi

# Extend LD_LIBRARY_PATH for torch and cudnn. Detected from the venv's own
# site-packages rather than a hardcoded python3.X -- pyproject.toml's
# supported version has moved before and will again.
SITE_PACKAGES="$("${PYTHON}" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
TORCH_LIB="${SITE_PACKAGES}/torch/lib"
CUDNN_LIB="${SITE_PACKAGES}/nvidia/cudnn/lib"
export LD_LIBRARY_PATH="${TORCH_LIB}:${CUDNN_LIB}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Start ollama if it's installed and not already running. Skipped entirely
# when the binary isn't on PATH (e.g. hosts that have moved to serving
# models via llama.cpp instead) -- otherwise this silently no-ops after
# burning the full 10s wait below on every restart.
if command -v ollama &>/dev/null && ! curl -sf "http://localhost:11434" &>/dev/null; then
    echo "Starting ollama serve..."
    ollama serve &
    OLLAMA_PID=$!
    trap 'kill "${OLLAMA_PID}" 2>/dev/null || true' EXIT
    # Wait up to 10s for ollama to be ready
    for i in $(seq 1 10); do
        curl -sf "http://localhost:11434" &>/dev/null && break
        sleep 1
    done
fi

# Secret key precedence:
#   1. WEBUI_SECRET_KEY already in environment (set by .env.local or a
#      systemd unit's EnvironmentFile via deploy/local/setup.sh)
#   2. Fallback: generate once into backend/.webui_secret_key for users who
#      skipped setup.sh
KEY_FILE="${BACKEND_DIR}/.webui_secret_key"
if [[ -z "${WEBUI_SECRET_KEY:-}" ]]; then
    if [[ ! -f "${KEY_FILE}" ]]; then
        echo "Generating WEBUI_SECRET_KEY (run deploy/local/setup.sh to manage this explicitly)..."
        head -c 12 /dev/random | base64 > "${KEY_FILE}"
    fi
    WEBUI_SECRET_KEY="$(cat "${KEY_FILE}")"
fi

echo "Starting open-webui on http://${HOST}:${PORT}"
echo "  Ollama: ${OLLAMA_BASE_URL}"

cd "${BACKEND_DIR}"
exec env \
    WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}" \
    OLLAMA_BASE_URL="${OLLAMA_BASE_URL}" \
    CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN}" \
    USER_AGENT="${USER_AGENT}" \
    LOKY_MAX_CPU_COUNT="${LOKY_MAX_CPU_COUNT}" \
    TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM}" \
    ${OPENAI_API_KEY:+OPENAI_API_KEY="${OPENAI_API_KEY}"} \
    ${OPENAI_API_BASE_URL:+OPENAI_API_BASE_URL="${OPENAI_API_BASE_URL}"} \
    ${WEBUI_ADMIN_EMAIL:+WEBUI_ADMIN_EMAIL="${WEBUI_ADMIN_EMAIL}"} \
    ${WEBUI_ADMIN_PASSWORD:+WEBUI_ADMIN_PASSWORD="${WEBUI_ADMIN_PASSWORD}"} \
    ${WEBUI_ADMIN_NAME:+WEBUI_ADMIN_NAME="${WEBUI_ADMIN_NAME}"} \
    "${PYTHON}" -m uvicorn open_webui.main:app \
        --host "${HOST}" \
        --port "${PORT}" \
        --forwarded-allow-ips "*" \
        --workers "${UVICORN_WORKERS}"

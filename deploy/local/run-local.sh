#!/usr/bin/env bash
# Run open-webui locally using the .venv Python install (no Docker).
# Expects: .venv built. Models are served via an OpenAI-compatible connection
# (llama.cpp, LMStudio, OpenAI, etc.) configured through deploy/local/setup.sh
# or .env.local -- this script doesn't manage a model server process itself.

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
UVICORN_WORKERS="${UVICORN_WORKERS:-1}"
CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-http://localhost:${PORT}}"
USER_AGENT="${USER_AGENT:-open-webui}"
LOKY_MAX_CPU_COUNT="${LOKY_MAX_CPU_COUNT:-1}"
TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"

usage() {
    echo "Usage: [PORT=8080] [HOST=0.0.0.0] $0"
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

cd "${BACKEND_DIR}"
exec env \
    WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}" \
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

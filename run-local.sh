#!/usr/bin/env bash
# Run open-webui locally using the .venv Python install (no Docker).
# Expects: .venv built, ollama on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/backend"
VENV="${SCRIPT_DIR}/.venv"
PYTHON="${VENV}/bin/python"

PORT="${PORT:-3000}"
HOST="${HOST:-0.0.0.0}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
UVICORN_WORKERS="${UVICORN_WORKERS:-1}"

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

# Extend LD_LIBRARY_PATH for torch and cudnn
TORCH_LIB="${VENV}/lib/python3.14/site-packages/torch/lib"
CUDNN_LIB="${VENV}/lib/python3.14/site-packages/nvidia/cudnn/lib"
export LD_LIBRARY_PATH="${TORCH_LIB}:${CUDNN_LIB}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Start ollama if not already running
if ! curl -sf "http://localhost:11434" &>/dev/null; then
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

# Generate or load secret key
KEY_FILE="${BACKEND_DIR}/.webui_secret_key"
if [[ -z "${WEBUI_SECRET_KEY:-}" ]]; then
    if [[ ! -f "${KEY_FILE}" ]]; then
        echo "Generating WEBUI_SECRET_KEY..."
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
    "${PYTHON}" -m uvicorn open_webui.main:app \
        --host "${HOST}" \
        --port "${PORT}" \
        --forwarded-allow-ips "*" \
        --workers "${UVICORN_WORKERS}"

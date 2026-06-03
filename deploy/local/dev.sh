#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV="${REPO_ROOT}/.venv"

if [[ ! -x "${VENV}/bin/python" ]]; then
    echo "ERROR: ${VENV} not found — run: python3 -m venv .venv && pip install -e backend" >&2
    exit 1
fi

export CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-http://localhost:5173;http://localhost:8080}"
export USER_AGENT="${USER_AGENT:-open-webui-agent}"
PORT="${PORT:-8080}"

cd "${REPO_ROOT}/backend"
exec "${VENV}/bin/python" -m uvicorn open_webui.main:app \
    --port "${PORT}" \
    --host 0.0.0.0 \
    --forwarded-allow-ips "${FORWARDED_ALLOW_IPS:-*}" \
    --reload

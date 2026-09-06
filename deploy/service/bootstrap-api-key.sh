#!/usr/bin/env bash
# Bootstrap default API key for the admin user.
# Run this after the first startup when WEBUI_DEFAULT_API_KEY is set.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_PATH="${REPO_ROOT}/backend/data/webui.db"
ENV_FILE="${1:-${HOME}/.config/open-webui/env}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: env file not found: $ENV_FILE" >&2
    exit 1
fi

if [[ ! -f "$DB_PATH" ]]; then
    echo "ERROR: database not found: $DB_PATH" >&2
    echo "Start the service first to initialize the database." >&2
    exit 1
fi

# Source the env file to get WEBUI_ADMIN_EMAIL and WEBUI_DEFAULT_API_KEY
set -o allexport
# shellcheck source=/dev/null
source "$ENV_FILE"
set +o allexport

if [[ -z "${WEBUI_ADMIN_EMAIL:-}" ]]; then
    echo "WEBUI_ADMIN_EMAIL not set in $ENV_FILE — skipping API key bootstrap" >&2
    exit 0
fi

if [[ -z "${WEBUI_DEFAULT_API_KEY:-}" ]]; then
    echo "WEBUI_DEFAULT_API_KEY not set in $ENV_FILE — skipping API key bootstrap" >&2
    exit 0
fi

# Check if admin user exists
user_id=$(sqlite3 "$DB_PATH" "SELECT id FROM user WHERE email = '$WEBUI_ADMIN_EMAIL' LIMIT 1;" 2>/dev/null || true)

if [[ -z "$user_id" ]]; then
    echo "ERROR: Admin user not found: $WEBUI_ADMIN_EMAIL" >&2
    echo "The admin user should be created on first startup." >&2
    exit 1
fi

# Check if the API key already exists. Schema (backend/open_webui/models/users.py
# ApiKey): id/user_id/key/data/expires_at/last_used_at/created_at/updated_at —
# the key column is `key`, not `api_key`, and timestamps are epoch seconds
# (BigInteger), not SQLite datetime() text. `id` has no DB-side default.
existing=$(sqlite3 "$DB_PATH" "SELECT 1 FROM api_key WHERE key = '$WEBUI_DEFAULT_API_KEY' LIMIT 1;" 2>/dev/null || true)

if [[ -n "$existing" ]]; then
    echo "API key already exists: $WEBUI_DEFAULT_API_KEY"
    exit 0
fi

# Insert the API key
sqlite3 "$DB_PATH" <<EOF
INSERT INTO api_key (id, user_id, key, created_at, updated_at)
VALUES (lower(hex(randomblob(16))), '${user_id}', '${WEBUI_DEFAULT_API_KEY}', strftime('%s','now'), strftime('%s','now'));
EOF

echo "Default API key added for ${WEBUI_ADMIN_EMAIL}: ${WEBUI_DEFAULT_API_KEY}"

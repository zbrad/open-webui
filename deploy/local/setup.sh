#!/usr/bin/env bash
# Interactive setup for open-webui environment configuration.
# Usage: setup.sh [--mode local|service]
#   local   — writes to <repo-root>/.env.local     (sourced by deploy/local/run-local.sh)
#   service — writes to ~/.config/open-webui/env   (read by the systemd --user unit)
#
# Re-running pre-fills all prompts from the existing file.
# Keys not covered by these prompts are preserved unchanged.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_ENV="${REPO_ROOT}/.env.local"
SERVICE_ENV="${HOME}/.config/open-webui/env"

# Keys this script manages — anything else in the existing file is preserved.
MANAGED_KEYS="PORT|HOST|UVICORN_WORKERS|CORS_ALLOW_ORIGIN|\
WEBUI_SECRET_KEY|OPENAI_API_KEY|OPENAI_API_BASE_URL|\
WEBUI_ADMIN_EMAIL|WEBUI_ADMIN_PASSWORD|WEBUI_ADMIN_NAME|WEBUI_DEFAULT_API_KEY"

# ── ANSI helpers ───────────────────────────────────────────────────────────────

bold=$'\033[1m'
reset=$'\033[0m'
green=$'\033[1;32m'
cyan=$'\033[0;36m'
dim=$'\033[2m'

header() { echo; printf "%b%s%b\n" "$bold$green" "$1" "$reset"; echo; }

# Prompt with a visible default. Press Enter to keep it.
ask() {
    local label="$1" default="$2" result_var="$3"
    local hint=""
    [[ -n "$default" ]] && hint=" ${dim}[${default}]${reset}"
    printf "%b%s%b%s: " "$bold" "$label" "$reset" "$hint"
    local value
    read -r value
    [[ -z "$value" ]] && value="$default"
    printf -v "$result_var" '%s' "$value"
}

# Read a key from an env file, stripping surrounding quotes.
read_env() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | sed "s/^['\"]//;s/['\"]$//" || true
}

# Collect lines from an existing env file that are NOT managed by this script.
read_extra_keys() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -E "^[A-Z_]+=" "$file" | grep -Ev "^(${MANAGED_KEYS})=" || true
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [--mode local|service]

  --mode local    Write to ${LOCAL_ENV}
  --mode service  Write to ${SERVICE_ENV} (read by the systemd --user unit)
  -h, --help      Show this help
EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────

MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)       MODE="$2"; shift 2 ;;
        --mode=*)     MODE="${1#--mode=}"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo
    echo "Select deployment target:"
    echo "  1) local   — ${LOCAL_ENV}"
    echo "  2) service — ${SERVICE_ENV}"
    printf "\nChoice [1/2]: "
    read -r choice
    case "$choice" in
        1|local)   MODE="local" ;;
        2|service) MODE="service" ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac
fi

case "$MODE" in
    local)   ENV_FILE="$LOCAL_ENV" ;;
    service) ENV_FILE="$SERVICE_ENV" ;;
    *)       echo "Unknown mode: $MODE (expected local or service)"; exit 1 ;;
esac

# ── Load existing values (pre-fill defaults) ───────────────────────────────────

e_port=$(read_env "$ENV_FILE" PORT)
e_host=$(read_env "$ENV_FILE" HOST)
e_workers=$(read_env "$ENV_FILE" UVICORN_WORKERS)
e_cors=$(read_env "$ENV_FILE" CORS_ALLOW_ORIGIN)
e_secret=$(read_env "$ENV_FILE" WEBUI_SECRET_KEY)
e_openai_key=$(read_env "$ENV_FILE" OPENAI_API_KEY)
e_openai_url=$(read_env "$ENV_FILE" OPENAI_API_BASE_URL)
e_admin_email=$(read_env "$ENV_FILE" WEBUI_ADMIN_EMAIL)
e_admin_name=$(read_env "$ENV_FILE" WEBUI_ADMIN_NAME)
e_api_key=$(read_env "$ENV_FILE" WEBUI_DEFAULT_API_KEY)
extra_keys=$(read_extra_keys "$ENV_FILE")

echo
printf "%b%s%b\n" "$bold$cyan" "open-webui setup — mode: ${MODE}" "$reset"
printf "%bTarget: %b%s\n" "$dim" "$reset" "$ENV_FILE"
[[ -f "$ENV_FILE" ]] && printf "%bPre-filling from existing file.%b\n" "$dim" "$reset"

# ── Server ─────────────────────────────────────────────────────────────────────

header "Server"
ask "Port"             "${e_port:-3000}"                        o_port
ask "Host"             "${e_host:-0.0.0.0}"                    o_host
ask "Uvicorn workers"  "${e_workers:-1}"                        o_workers
default_cors="$([[ "$MODE" == "service" ]] && echo "*" || echo "http://localhost:${o_port}")"
ask "CORS allow origin" "${e_cors:-${default_cors}}" o_cors

# ── Secret key ─────────────────────────────────────────────────────────────────

header "Secret key  ${dim}(signs all JWTs — changing it invalidates active sessions)${reset}"

GENERATE_SECRET=false
if [[ -n "$e_secret" ]]; then
    printf "%bWebUI secret key%b ${dim}[<existing — Enter to keep, 'r' to regenerate>]%b: " "$bold" "$reset" "$reset"
    read -r sk_choice
    if [[ "${sk_choice,,}" == "r" ]]; then
        GENERATE_SECRET=true
    elif [[ -n "$sk_choice" ]]; then
        e_secret="$sk_choice"
    fi
else
    printf "%bWebUI secret key%b ${dim}[Enter to auto-generate, or type a value]%b: " "$bold" "$reset" "$reset"
    read -rs sk_input
    echo
    [[ -z "$sk_input" ]] && GENERATE_SECRET=true || e_secret="$sk_input"
fi

if [[ "$GENERATE_SECRET" == "true" ]]; then
    e_secret="$(head -c 24 /dev/random | base64)"
    echo "  Generated new secret key."
fi
o_secret="$e_secret"

# ── OpenAI-compatible API ──────────────────────────────────────────────────────

header "OpenAI-compatible API  ${dim}(leave blank to skip)${reset}"
ask "API key"      "${e_openai_key:-}"                           o_openai_key
ask "API base URL" "${e_openai_url:-https://api.openai.com/v1}" o_openai_url

# ── Admin bootstrap ────────────────────────────────────────────────────────────

header "Admin user bootstrap  ${dim}(optional — only used on first startup)${reset}"
ask "Admin email"    "${e_admin_email:-}"     o_admin_email

# Only prompt for password and API key if admin email is set
if [[ -n "$o_admin_email" ]]; then
    printf "%bAdmin password%b ${dim}[Enter to skip / unchanged]%b: " "$bold" "$reset" "$reset"
    read -rs o_admin_password; echo
    ask "Admin name"     "${e_admin_name:-Admin}" o_admin_name

    # Generate default API key if none exists
    default_api_key="${e_api_key:-sk-$(head -c 16 /dev/random | xxd -p -c 32)}"
    ask "Default API key" "${default_api_key}" o_api_key
else
    o_admin_password=""
    o_admin_name=""
    o_api_key=""
fi

# ── Preview ────────────────────────────────────────────────────────────────────

echo
printf "%b%s%b\n" "$bold" "Configuration to write:" "$reset"
printf "  %-28s %s\n" "PORT"              "$o_port"
printf "  %-28s %s\n" "HOST"              "$o_host"
printf "  %-28s %s\n" "UVICORN_WORKERS"   "$o_workers"
printf "  %-28s %s\n" "CORS_ALLOW_ORIGIN" "$o_cors"
printf "  %-28s %s\n" "WEBUI_SECRET_KEY"  "<set>"
[[ -n "$o_openai_key" ]]    && printf "  %-28s %s\n" "OPENAI_API_KEY"       "<set>"
[[ -n "$o_openai_url" ]]    && printf "  %-28s %s\n" "OPENAI_API_BASE_URL"  "$o_openai_url"
[[ -n "$o_admin_email" ]]    && printf "  %-28s %s\n" "WEBUI_ADMIN_EMAIL"    "$o_admin_email"
[[ -n "$o_admin_password" ]] && printf "  %-28s %s\n" "WEBUI_ADMIN_PASSWORD" "<set>"
[[ -n "$o_admin_name" ]]     && printf "  %-28s %s\n" "WEBUI_ADMIN_NAME"     "$o_admin_name"
[[ -n "$o_api_key" ]]        && printf "  %-28s %s\n" "WEBUI_DEFAULT_API_KEY" "$o_api_key"
if [[ -n "$extra_keys" ]]; then
    echo
    printf "  %b(preserved from existing file)%b\n" "$dim" "$reset"
    while IFS= read -r line; do
        printf "  %b%s%b\n" "$dim" "$line" "$reset"
    done <<< "$extra_keys"
fi

echo
printf "Write to %b%s%b? [Y/n]: " "$bold" "$ENV_FILE" "$reset"
read -r confirm
[[ "${confirm,,}" == "n" ]] && echo "Aborted." && exit 0

# ── Write env file ─────────────────────────────────────────────────────────────

mkdir -p "$(dirname "$ENV_FILE")"

cat > "$ENV_FILE" <<EOF
# open-webui environment — $(date)
# Mode: ${MODE}  |  Managed by deploy/local/setup.sh

PORT=${o_port}
HOST=${o_host}
UVICORN_WORKERS=${o_workers}
CORS_ALLOW_ORIGIN=${o_cors}

WEBUI_SECRET_KEY=${o_secret}
EOF

if [[ -n "$o_openai_key" ]]; then
    printf "\nOPENAI_API_KEY=%s\nOPENAI_API_BASE_URL=%s\n" \
        "$o_openai_key" "$o_openai_url" >> "$ENV_FILE"
fi

if [[ -n "$o_admin_email" ]]; then
    printf "\nWEBUI_ADMIN_EMAIL=%s\nWEBUI_ADMIN_PASSWORD=%s\nWEBUI_ADMIN_NAME=%s\n" \
        "$o_admin_email" "$o_admin_password" "$o_admin_name" >> "$ENV_FILE"
    [[ -n "$o_api_key" ]] && printf "WEBUI_DEFAULT_API_KEY=%s\n" "$o_api_key" >> "$ENV_FILE"
fi

if [[ -n "$extra_keys" ]]; then
    printf "\n# preserved from previous configuration\n" >> "$ENV_FILE"
    echo "$extra_keys" >> "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"

echo
printf "%b%s%b\n" "$green$bold" "Saved to ${ENV_FILE}" "$reset"

if [[ "$MODE" == "local" ]]; then
    echo "Run: make local-start   (or deploy/local/run-local.sh)"
else
    echo "Run: systemctl --user restart open-webui"
fi

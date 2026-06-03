#!/usr/bin/env bash
# Deploy open-webui as a systemd service.
# Run after: deploy/local/setup.sh --mode service
# Run as root or with sudo.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
INSTALL_DIR="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
SERVICE_USER="${SERVICE_USER:-$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")}"
ENV_DEST="/etc/open-webui/env"
UNIT_DEST="/etc/systemd/system/open-webui.service"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Re-running with sudo..." >&2
    exec sudo SERVICE_USER="${SERVICE_USER}" bash "$0" "$@"
fi

echo "Installing open-webui service"
echo "  install dir : ${INSTALL_DIR}"
echo "  service user: ${SERVICE_USER}"

mkdir -p /etc/open-webui
if [[ ! -f "${ENV_DEST}" ]]; then
    cp "${SCRIPT_DIR}/open-webui.env" "${ENV_DEST}"
    echo "Created ${ENV_DEST} — edit to customise before starting"
else
    echo "Skipping ${ENV_DEST} (already exists)"
fi
chmod 600 "${ENV_DEST}"

sed \
    -e "s|__USER__|${SERVICE_USER}|g" \
    -e "s|__INSTALL_DIR__|${INSTALL_DIR}|g" \
    "${SCRIPT_DIR}/open-webui.service" > "${UNIT_DEST}"
chmod 644 "${UNIT_DEST}"

systemctl daemon-reload
systemctl enable open-webui
echo ""
echo "Service installed."
echo ""
echo "Next: configure the environment (sets WEBUI_SECRET_KEY and optional API keys):"
echo "  deploy/local/setup.sh --mode service"
echo ""
echo "Then start:"
echo "  sudo systemctl start open-webui"
echo "  sudo systemctl status open-webui"
echo "  journalctl -u open-webui -f"

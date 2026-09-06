#!/usr/bin/env bash
# Install open-webui as a systemd --user service (no root needed).
# Run after: deploy/local/setup.sh --mode service

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
INSTALL_DIR="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
ENV_DEST="${HOME}/.config/open-webui/env"
UNIT_DEST="${HOME}/.config/systemd/user/open-webui.service"

echo "Installing open-webui user service"
echo "  install dir: ${INSTALL_DIR}"
echo "  unit file  : ${UNIT_DEST}"
echo "  env file   : ${ENV_DEST}"

mkdir -p "$(dirname "${ENV_DEST}")"
if [[ ! -f "${ENV_DEST}" ]]; then
    cp "${SCRIPT_DIR}/open-webui.env" "${ENV_DEST}"
    echo "Created ${ENV_DEST} — edit it, or run deploy/local/setup.sh --mode service, before starting"
else
    echo "Skipping ${ENV_DEST} (already exists)"
fi
chmod 600 "${ENV_DEST}"

mkdir -p "$(dirname "${UNIT_DEST}")"
sed \
    -e "s|__INSTALL_DIR__|${INSTALL_DIR}|g" \
    -e "s|__ENV_FILE__|${ENV_DEST}|g" \
    "${SCRIPT_DIR}/open-webui.service" > "${UNIT_DEST}"

systemctl --user daemon-reload
systemctl --user enable open-webui

echo ""
echo "Service installed."
echo ""
if [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" != "yes" ]]; then
    echo "NOTE: lingering is not enabled for this user — the service will stop"
    echo "when your last session logs out. To have it survive logout/reboot:"
    echo "  sudo loginctl enable-linger $(id -un)"
    echo ""
fi
echo "Next: configure the environment (sets WEBUI_SECRET_KEY and optional API keys):"
echo "  deploy/local/setup.sh --mode service"
echo ""
echo "Then start:"
echo "  systemctl --user start open-webui"
echo "  systemctl --user status open-webui"
echo "  journalctl --user -u open-webui -f"

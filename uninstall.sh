#!/usr/bin/env bash
set -euo pipefail

APP_NAME="audiobridge"
INSTALL_DIR="${HOME}/.local/share/${APP_NAME}"
SERVICE_NAME="${APP_NAME}.service"
UDEV_RULE="99-${APP_NAME}.rules"
CERT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/${APP_NAME}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }

echo ""
echo "  AudioBridge Uninstaller"
echo "  ───────────────────────"
echo ""

# Stop and disable service
if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null; then
    info "Stopping service..."
    systemctl --user stop "${SERVICE_NAME}"
fi

if systemctl --user is-enabled "${SERVICE_NAME}" &>/dev/null; then
    info "Disabling service..."
    systemctl --user disable "${SERVICE_NAME}"
fi

# Remove service file
if [ -f "${HOME}/.config/systemd/user/${SERVICE_NAME}" ]; then
    info "Removing systemd service..."
    rm -f "${HOME}/.config/systemd/user/${SERVICE_NAME}"
    systemctl --user daemon-reload
fi

# Remove udev rule
if [ -f "/etc/udev/rules.d/${UDEV_RULE}" ]; then
    info "Removing udev rule (requires sudo)..."
    sudo rm -f "/etc/udev/rules.d/${UDEV_RULE}"
    sudo udevadm control --reload-rules
fi

# Remove app files
if [ -d "${INSTALL_DIR}" ]; then
    info "Removing application files..."
    rm -rf "${INSTALL_DIR}"
fi

# Remove certs and config
if [ -d "${CERT_DIR}" ]; then
    info "Removing certificates and config..."
    rm -rf "${CERT_DIR}"
fi

ok "AudioBridge has been uninstalled"
echo ""

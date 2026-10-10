#!/usr/bin/env bash
set -euo pipefail

APP="audiobridge"
DIR="${HOME}/.local/share/${APP}"
VENV="${DIR}/venv"
SERVICE="${APP}.service"
UDEV="99-${APP}.rules"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '\033[0;36m[*]\033[0m %s\n' "$1"; }
ok()   { printf '\033[0;32m[+]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$1"; }
die()  { printf '\033[0;31m[x]\033[0m %s\n' "$1"; exit 1; }

detect_distro() {
    [ -f /etc/os-release ] && . /etc/os-release && echo "${ID}" || echo "unknown"
}

install_deps() {
    local distro
    distro="$(detect_distro)"
    info "Distro: ${distro}"

    local missing=()
    command -v python3 &>/dev/null || missing+=("python3")
    command -v parec   &>/dev/null || missing+=("parec")
    command -v openssl &>/dev/null || missing+=("openssl")

    [ ${#missing[@]} -eq 0 ] && { ok "Dependencies satisfied"; return; }

    info "Installing: ${missing[*]}"
    case "${distro}" in
        arch|endeavouros|manjaro|garuda|artix|cachyos)
            sudo pacman -S --needed --noconfirm python openssl \
                $(pacman -Qi pipewire-pulse &>/dev/null && echo "" || echo "pipewire-pulse") ;;
        fedora|nobara)
            sudo dnf install -y python3 openssl pipewire-pulseaudio ;;
        ubuntu|debian|pop|linuxmint|zorin|elementary)
            sudo apt-get update && sudo apt-get install -y python3 python3-venv openssl pulseaudio-utils ;;
        opensuse*|suse*)
            sudo zypper install -y python3 openssl pipewire-pulseaudio ;;
        void)
            sudo xbps-install -Sy python3 openssl pulseaudio-utils ;;
        nixos)
            warn "NixOS: add python3, openssl, pulseaudio to environment.systemPackages" ;;
        *)
            warn "Unknown distro. Install manually: python3, openssl, parec" ;;
    esac
}

install_app() {
    info "Installing to ${DIR}"
    mkdir -p "${DIR}/web"
    cp "${SRC}/server.py"       "${DIR}/server.py"
    cp "${SRC}/web/index.html"  "${DIR}/web/index.html"

    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" install --quiet --upgrade pip
    "${VENV}/bin/pip" install --quiet websockets
    ok "App installed"
}

setup_service() {
    info "Configuring systemd service"
    mkdir -p "${HOME}/.config/systemd/user"

    cat > "${HOME}/.config/systemd/user/${SERVICE}" <<EOF
[Unit]
Description=AudioBridge
After=pipewire-pulse.service pulseaudio.service
Wants=pipewire-pulse.service

[Service]
Type=simple
ExecStart=${VENV}/bin/python3 -u ${DIR}/server.py
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE}"
    loginctl enable-linger "$(whoami)" 2>/dev/null || true
    ok "Service enabled"
}

setup_udev() {
    info "Installing udev rule"
    local uid="$(id -u)"

    cat > "/tmp/${UDEV}" <<EOF
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", RUN+="/usr/bin/su $(whoami) -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user start ${SERVICE}'"
ACTION=="remove", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", RUN+="/usr/bin/su $(whoami) -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user stop ${SERVICE}'"
EOF

    sudo cp "/tmp/${UDEV}" "/etc/udev/rules.d/${UDEV}"
    sudo udevadm control --reload-rules
    rm -f "/tmp/${UDEV}"
    ok "udev rule installed"
}

setup_firewall() {
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        sudo firewall-cmd --zone=public --add-port=8000/tcp --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        ok "Firewalld: port 8000 opened"
    elif command -v ufw &>/dev/null && sudo ufw status | grep -q "active"; then
        sudo ufw allow 8000/tcp 2>/dev/null || true
        ok "UFW: port 8000 opened"
    fi
}

generate_certs() {
    local cert_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/audiobridge/certs"
    mkdir -p "${cert_dir}"
    "${VENV}/bin/python3" -c "
import sys; sys.path.insert(0, '${DIR}')
from server import ensure_certs
ensure_certs('${cert_dir}')
"
    ok "Certificates ready"
}

start() {
    info "Starting AudioBridge"
    systemctl --user start "${SERVICE}"
    sleep 1
    systemctl --user is-active "${SERVICE}" &>/dev/null \
        && ok "Running" \
        || die "Failed to start. Run: journalctl --user -u ${SERVICE}"
}

summary() {
    echo ""
    echo "  AudioBridge installed."
    echo ""
    echo "  First-time iPhone setup:"
    echo "    1. Safari -> https://$(hostname).local:8000/ca.crt to grab the CA cert"
    echo "    2. Settings -> General -> VPN & Device Management -> install it"
    echo "    3. Settings -> General -> About -> Certificate Trust -> enable it"
    echo "    4. Safari -> https://$(hostname).local:8000"
    echo ""
    echo "  Commands:"
    echo "    systemctl --user {start,stop,restart,status} audiobridge"
    echo "    journalctl --user -u audiobridge -f"
    echo ""
}

main() {
    echo ""
    echo "  AudioBridge Installer"
    echo ""
    install_deps
    install_app
    setup_service
    setup_udev
    setup_firewall
    generate_certs
    start
    summary
}

main "$@"

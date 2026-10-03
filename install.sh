#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# AudioBridge — Installer
#
# Supports: Arch, Fedora, Debian/Ubuntu, openSUSE, Void, NixOS
# Supports: systemd (with or without user lingering)
# ──────────────────────────────────────────────────────────────

APP_NAME="audiobridge"
INSTALL_DIR="${HOME}/.local/share/${APP_NAME}"
VENV_DIR="${INSTALL_DIR}/venv"
SERVICE_NAME="${APP_NAME}.service"
UDEV_RULE="99-${APP_NAME}.rules"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }

# ──────────────────────────────────────────────────────────────
# Detect distro + package manager
# ──────────────────────────────────────────────────────────────
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    else
        echo "unknown"
    fi
}

install_deps() {
    local distro
    distro="$(detect_distro)"
    info "Detected distro: ${distro}"

    local deps_needed=()

    # Check for python3
    if ! command -v python3 &>/dev/null; then
        deps_needed+=("python3")
    fi

    # Check for pactl / parec (pulseaudio-utils or pipewire-pulse)
    if ! command -v parec &>/dev/null; then
        deps_needed+=("parec")
    fi

    # Check for openssl
    if ! command -v openssl &>/dev/null; then
        deps_needed+=("openssl")
    fi

    if [ ${#deps_needed[@]} -eq 0 ]; then
        ok "All dependencies already installed"
        return
    fi

    info "Missing tools: ${deps_needed[*]}"
    info "Installing system dependencies..."

    case "${distro}" in
        arch|endeavouros|manjaro|garuda|artix|cachyos)
            sudo pacman -S --needed --noconfirm \
                python openssl \
                $(pacman -Qi pipewire-pulse &>/dev/null && echo "" || echo "pipewire-pulse")
            ;;
        fedora|nobara)
            sudo dnf install -y python3 openssl pipewire-pulseaudio
            ;;
        ubuntu|debian|pop|linuxmint|zorin|elementary)
            sudo apt-get update
            sudo apt-get install -y python3 python3-venv openssl pulseaudio-utils
            ;;
        opensuse*|suse*)
            sudo zypper install -y python3 openssl pipewire-pulseaudio
            ;;
        void)
            sudo xbps-install -Sy python3 openssl pulseaudio-utils
            ;;
        nixos)
            warn "On NixOS, add pulseaudio, openssl, and python3 to your environment.systemPackages"
            ;;
        *)
            warn "Unknown distro '${distro}'. Please install manually: python3, openssl, parec (pulseaudio-utils or pipewire-pulse)"
            ;;
    esac
}

# ──────────────────────────────────────────────────────────────
# Install application
# ──────────────────────────────────────────────────────────────
install_app() {
    info "Installing AudioBridge to ${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}/web"

    cp "${SCRIPT_DIR}/server.py" "${INSTALL_DIR}/server.py"
    cp "${SCRIPT_DIR}/web/index.html" "${INSTALL_DIR}/web/index.html"

    info "Creating Python virtual environment..."
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
    "${VENV_DIR}/bin/pip" install --quiet websockets

    ok "Application installed"
}

# ──────────────────────────────────────────────────────────────
# Setup systemd user service
# ──────────────────────────────────────────────────────────────
setup_service() {
    info "Setting up systemd user service..."
    mkdir -p "${HOME}/.config/systemd/user"

    cat > "${HOME}/.config/systemd/user/${SERVICE_NAME}" << EOF
[Unit]
Description=AudioBridge — System Audio Streamer
After=pipewire-pulse.service pulseaudio.service
Wants=pipewire-pulse.service

[Service]
Type=simple
ExecStart=${VENV_DIR}/bin/python3 -u ${INSTALL_DIR}/server.py
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE_NAME}"
    ok "Service installed and enabled"

    # Enable lingering so the service starts at boot (before login)
    if command -v loginctl &>/dev/null; then
        loginctl enable-linger "$(whoami)" 2>/dev/null || true
    fi
}

# ──────────────────────────────────────────────────────────────
# Setup udev rule for iPhone auto-start
# ──────────────────────────────────────────────────────────────
setup_udev() {
    info "Setting up udev rule for iPhone auto-start..."

    local uid
    uid="$(id -u)"

    cat > "/tmp/${UDEV_RULE}" << EOF
# AudioBridge: auto-start/stop when iPhone is connected via USB
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", RUN+="/usr/bin/su $(whoami) -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user start ${SERVICE_NAME}'"
ACTION=="remove", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", RUN+="/usr/bin/su $(whoami) -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user stop ${SERVICE_NAME}'"
EOF

    sudo cp "/tmp/${UDEV_RULE}" "/etc/udev/rules.d/${UDEV_RULE}"
    sudo udevadm control --reload-rules
    rm -f "/tmp/${UDEV_RULE}"
    ok "udev rule installed"
}

# ──────────────────────────────────────────────────────────────
# Setup firewall
# ──────────────────────────────────────────────────────────────
setup_firewall() {
    info "Configuring firewall..."

    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        sudo firewall-cmd --zone=public --add-port=8000/tcp --permanent 2>/dev/null || true
        sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        ok "Firewalld: ports 8000, 8080 opened"
    elif command -v ufw &>/dev/null && sudo ufw status | grep -q "active"; then
        sudo ufw allow 8000/tcp 2>/dev/null || true
        sudo ufw allow 8080/tcp 2>/dev/null || true
        ok "UFW: ports 8000, 8080 opened"
    elif command -v iptables &>/dev/null; then
        sudo iptables -A INPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null || true
        sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
        ok "iptables: ports 8000, 8080 opened"
    else
        warn "No firewall detected — ports should be open by default"
    fi
}

# ──────────────────────────────────────────────────────────────
# Generate certs + show iOS install instructions
# ──────────────────────────────────────────────────────────────
first_run() {
    info "Generating TLS certificates on first start..."
    "${VENV_DIR}/bin/python3" "${INSTALL_DIR}/server.py" --help > /dev/null 2>&1

    local cert_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/audiobridge/certs"
    mkdir -p "${cert_dir}"

    # Generate certs by doing a quick dry-run
    "${VENV_DIR}/bin/python3" -c "
import sys
sys.path.insert(0, '${INSTALL_DIR}')
from server import ensure_certs
ensure_certs('${cert_dir}')
"

    ok "Certificates generated at ${cert_dir}"
}

# ──────────────────────────────────────────────────────────────
# Start service
# ──────────────────────────────────────────────────────────────
start_service() {
    info "Starting AudioBridge..."
    systemctl --user start "${SERVICE_NAME}"
    sleep 1

    if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null; then
        ok "AudioBridge is running"
    else
        err "Service failed to start. Check: journalctl --user -u ${SERVICE_NAME}"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────
# Print summary
# ──────────────────────────────────────────────────────────────
print_summary() {
    local hostname_val
    hostname_val="$(hostname)"

    local cert_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/audiobridge/certs"
    local ca_cert="${cert_dir}/ca-cert.crt"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  AudioBridge installed successfully${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  First-time iPhone setup:"
    echo ""
    echo "  1. On your iPhone, open Safari and go to:"
    echo -e "     ${CYAN}http://<your-pc-ip>:8080${NC}"
    echo "     to download the CA certificate."
    echo ""
    echo "  2. Go to Settings > General > VPN & Device Management"
    echo "     and install the 'AudioBridge CA' profile."
    echo ""
    echo "  3. Go to Settings > General > About > Certificate Trust Settings"
    echo "     and enable full trust for 'AudioBridge CA'."
    echo ""
    echo "  4. Open Safari and go to:"
    echo -e "     ${CYAN}https://${hostname_val}.local:8000${NC}"
    echo ""
    echo "  Commands:"
    echo "    Start:   systemctl --user start audiobridge"
    echo "    Stop:    systemctl --user stop audiobridge"
    echo "    Status:  systemctl --user status audiobridge"
    echo "    Logs:    journalctl --user -u audiobridge -f"
    echo ""
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "  AudioBridge Installer"
    echo "  ─────────────────────"
    echo ""

    install_deps
    install_app
    setup_service
    setup_udev
    setup_firewall
    first_run
    start_service
    print_summary
}

main "$@"

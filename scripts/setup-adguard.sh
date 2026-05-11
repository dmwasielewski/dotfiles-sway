#!/bin/bash
# setup-adguard.sh — install AdGuard for Linux on Fedora Atomic

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-adguard.sh"

INSTALL_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardCLI/release/install.sh"
INSTALL_DIR="/opt/adguard-cli"
INSTALL_BIN="$INSTALL_DIR/adguard-cli"
SYMLINK_BIN="/usr/local/bin/adguard-cli"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   AdGuard for Linux — CLI setup         ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

ensure_prereqs() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required to install AdGuard for Linux" >&2
        return 1
    fi
    if ! command -v iptables >/dev/null 2>&1; then
        echo "iptables is required for AdGuard for Linux auto mode" >&2
        return 1
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required; run 'sudo -v' in a terminal and rerun this script" >&2
        return 1
    fi
}

has_adguard_cli() {
    command -v adguard-cli >/dev/null 2>&1 || [[ -x "$INSTALL_BIN" ]]
}

install_adguard() {
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"; trap - RETURN' RETURN

    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$INSTALL_DIR"
    touch "$INSTALL_DIR/.nosymlink"

    curl -fsSL "$INSTALL_URL" -o "$tmp"
    sh "$tmp" -v

    if [[ -x "$INSTALL_BIN" ]] && [[ ! -x "$SYMLINK_BIN" ]]; then
        sudo ln -sf "$INSTALL_BIN" "$SYMLINK_BIN"
    fi
}

run_step "ADGUARD_PREREQS" "Checking AdGuard prerequisites" ensure_prereqs

if has_adguard_cli; then
    echo "==> AdGuard CLI already installed — skipping install."
    if [[ -x "$INSTALL_BIN" ]] && [[ ! -x "$SYMLINK_BIN" ]]; then
        sudo ln -sf "$INSTALL_BIN" "$SYMLINK_BIN"
    fi
    step_done "ADGUARD_CLI"
else
    run_step "ADGUARD_CLI" "Installing AdGuard for Linux" install_adguard
fi

if has_adguard_cli; then
    step_done "ADGUARD_READY"
else
    step_failed "ADGUARD_READY"
    echo -e "${YELLOW}⚠ AdGuard CLI is still missing after installation attempt${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} AdGuard for Linux installed${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Manual first-time setup:"
echo "  1. adguard-cli activate"
echo "  2. adguard-cli configure"
echo "  3. adguard-cli start"
echo ""
echo "Daily CLI usage:"
echo "  adguard-cli status"
echo "  adguard-cli start"
echo "  adguard-cli stop"
echo ""
print_state_summary

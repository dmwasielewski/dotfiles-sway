#!/bin/bash
# setup-nordvpn.sh — install NordVPN CLI on Fedora Atomic

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-nordvpn.sh"

REPO_FILE="/etc/yum.repos.d/nordvpn.repo"
KEY_FILE="/etc/pki/rpm-gpg/RPM-GPG-KEY-NordVPN"
REPO_URL="https://repo.nordvpn.com/yum/nordvpn/centos"
KEY_URL="https://repo.nordvpn.com/yum/nordvpn/centos/noarch/Packages/n/nordvpn-release-1.0.0-1.noarch.rpm"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   NordVPN — CLI setup                    ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

ensure_repo() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    if ! command -v rpm2cpio >/dev/null 2>&1; then
        echo "rpm2cpio is required to unpack the NordVPN release RPM" >&2
        return 1
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required; run 'sudo -v' in a terminal and rerun this script" >&2
        return 1
    fi

    curl -fL -o "$tmpdir/nordvpn-release.rpm" "$KEY_URL"
    (cd "$tmpdir" && rpm2cpio nordvpn-release.rpm | cpio -idm >/dev/null 2>&1)

    sudo -n install -Dm0644 "$tmpdir/etc/pki/rpm-gpg/RPM-GPG-KEY-NordVPN" "$KEY_FILE"
    sudo -n install -Dm0644 /dev/null "$REPO_FILE"
    sudo -n tee "$REPO_FILE" >/dev/null <<EOF
####################################################################
# NordVPN releases, stable                                         #
####################################################################
[nordvpn]
name = NordVPN YUM repository - \$basearch
baseurl = ${REPO_URL}/\$basearch
enabled = 1
gpgcheck = 1
gpgkey = file://${KEY_FILE}

[nordvpn-noarch]
name = NordVPN YUM repository - noarch
baseurl = ${REPO_URL}/noarch
enabled = 1
gpgcheck = 1
gpgkey = file://${KEY_FILE}
EOF
}

run_step "NORDVPN_REPO" "Configuring NordVPN repository" ensure_repo

if command -v nordvpn >/dev/null 2>&1; then
    echo "==> NordVPN CLI already installed — skipping install."
    step_done "NORDVPN_CLI"
else
    run_step "NORDVPN_CLI" "Installing NordVPN CLI" sudo -n rpm-ostree install nordvpn
fi

if getent group nordvpn >/dev/null 2>&1; then
    if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx nordvpn; then
        echo "==> User already in nordvpn group — skipping."
        step_done "NORDVPN_GROUP"
    else
        run_step_warn "NORDVPN_GROUP" "Adding user to nordvpn group" sudo usermod -aG nordvpn "$USER"
        echo "==> Re-log in or reboot so the nordvpn group membership takes effect."
    fi
else
    echo -e "${YELLOW}⚠ nordvpn group not present yet — finish login/reboot after the CLI install${NC}"
fi

step_done "NORDVPN_READY"

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} NordVPN CLI setup complete${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Check status with: nordvpn status"
echo "Connect with:       nordvpn connect"
echo "Disconnect with:    nordvpn disconnect"
echo ""

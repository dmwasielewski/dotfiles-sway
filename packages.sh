#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles-sway"
if [[ -f "$DOTFILES/scripts/lib-install.sh" ]]; then
    source "$DOTFILES/scripts/lib-install.sh"
    setup_logging "packages.sh"
fi

# Verify sudo works non-interactively and extend timeout for this install phase.
sudo -n true
echo "Defaults timestamp_timeout=30" | sudo tee /etc/sudoers.d/timeout > /dev/null

# Run this once after fresh install, then reboot
echo "==> Layering system packages (reboot required after)..."

# mako        - notification daemon
# libva-utils - VA-API hardware acceleration tools
# clipman     - clipboard history manager
# distrobox   - Ubuntu container support
# unzip       - required by setup.sh for font installation
# qemu-kvm    - KVM virtualisation engine
# libvirt     - virtualisation management daemon
# libvirt-daemon-config-network - default NAT network for VMs
# virt-manager  - GUI VM manager
# virt-viewer   - VM display viewer
# virt-install  - CLI VM creation tool
# bridge-utils  - network bridging for VMs
# wtype       - Wayland keyboard input injection (used by voice typing)
# alsa-utils  - arecord audio recording (used by voice typing)
# neovim      - modern text editor (Vim fork), available system-wide
# gitleaks    - secret scanner, enforced by the repo pre-push hook
# ripgrep/fd-find/fzf/wl-clipboard/python3-virtualenv/ShellCheck/libwebp-tools/nodejs/npm/make
#             - CLI dependencies used by Chris Titus Tech's Neovim config
PACKAGES="mako libva-utils clipman distrobox unzip qemu-kvm libvirt libvirt-daemon-config-network virt-manager virt-viewer virt-install bridge-utils wtype alsa-utils neovim gitleaks ripgrep fd-find fzf wl-clipboard python3-virtualenv ShellCheck libwebp-tools nodejs npm make"

# Intel GPU check
if lspci | grep -qi "Intel.*Graphics"; then
    echo "==> Intel GPU detected - adding intel-media-driver"
    PACKAGES="$PACKAGES intel-media-driver"
fi

# Filter out packages already installed (rpm-ostree errors on already-layered packages)
MISSING=()
for pkg in $PACKAGES; do
    if rpm -q "$pkg" &>/dev/null 2>&1; then
        echo "==> $pkg already installed — skipping"
    else
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
    echo "==> All packages already installed — nothing to do."
else
    echo "==> Installing new packages: ${MISSING[*]}"
    sudo rpm-ostree install "${MISSING[@]}"
fi

# AMD GPU check
if lspci | grep -qi "AMD\|ATI"; then
    echo "==> AMD GPU detected - mesa-va-drivers should already be present"
    echo "==> If video is not smooth after reboot, run: vainfo"
fi

# Check for nomodeset (breaks AMD GPU)
if rpm-ostree kargs | grep -q "nomodeset"; then
    echo "==> WARNING: nomodeset detected - removing it (breaks AMD GPU acceleration)"
    sudo rpm-ostree kargs --delete=nomodeset
fi

# Verify hardware acceleration
echo "==> Verifying hardware acceleration..."
if ls /dev/dri/renderD128 &>/dev/null; then
    echo "==> render node found - hardware acceleration available"
else
    echo "==> WARNING: /dev/dri/renderD128 missing - check GPU drivers"
fi

# Firewall
echo "==> Configuring firewall..."
if sudo firewall-cmd --permanent --query-service=dhcpv6-client >/dev/null 2>&1; then
    sudo firewall-cmd --remove-service=dhcpv6-client --permanent
else
    echo "==> dhcpv6-client already absent from the permanent firewall config — skipping"
fi
sudo firewall-cmd --reload

# NordVPN CLI
bash "$DOTFILES/scripts/setup-nordvpn.sh"

# AdGuard for Linux CLI
bash "$DOTFILES/scripts/setup-adguard.sh"

echo "==> Done. Please reboot: systemctl reboot"

#!/bin/bash
set -e

# Run this once after fresh install, then reboot
echo "==> Layering system packages (reboot required after)..."

# mako        - notification daemon
# libva-utils - VA-API hardware acceleration tools
# clipman     - clipboard history manager
# distrobox   - Ubuntu container support
# unzip       - required by setup.sh for font installation
PACKAGES="mako libva-utils clipman distrobox unzip"

# Intel GPU check
if lspci | grep -qi "Intel.*Graphics"; then
    echo "==> Intel GPU detected - adding intel-media-driver"
    PACKAGES="$PACKAGES intel-media-driver"
fi

rpm-ostree install $PACKAGES

# AMD GPU check
if lspci | grep -qi "AMD\|ATI"; then
    echo "==> AMD GPU detected - mesa-va-drivers should already be present"
    echo "==> If video is not smooth after reboot, run: vainfo"
fi

# Check for nomodeset (breaks AMD GPU)
if rpm-ostree kargs | grep -q "nomodeset"; then
    echo "==> WARNING: nomodeset detected - removing it (breaks AMD GPU acceleration)"
    rpm-ostree kargs --delete=nomodeset
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
sudo firewall-cmd --remove-service=dhcpv6-client --permanent
sudo firewall-cmd --reload

echo "==> Done. Please reboot: systemctl reboot"

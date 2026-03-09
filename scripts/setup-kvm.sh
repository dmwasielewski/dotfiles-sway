#!/bin/bash
# Setup KVM/QEMU virtualisation — run once after reboot post rpm-ostree install
# Requirements: qemu-kvm, libvirt, libvirt-daemon-config-network, virt-manager,
#               virt-viewer, bridge-utils must be layered via packages.sh first

set -e

echo "==> Enabling libvirtd service..."
sudo systemctl enable --now libvirtd

echo "==> Adding user to libvirt group..."
sudo usermod -aG libvirt "$USER"

echo "==> Starting default NAT network..."
sudo virsh net-autostart default
sudo virsh net-start default 2>/dev/null || echo "==> Default network already active."

echo "==> Verifying KVM..."
if ls /dev/kvm &>/dev/null; then
    echo "==> /dev/kvm found — KVM acceleration available."
else
    echo "==> WARNING: /dev/kvm missing. Check BIOS — enable AMD-V / Intel VT-x."
fi

echo ""
echo "=============================================="
echo " KVM ready!"
echo ""
echo " NOTE: Log out and back in for group changes"
echo "       to take effect, then run:"
echo "   virt-manager"
echo ""
echo " Recommended VM specs:"
echo "   Windows 11:     4 vCPU, 8GB RAM, 80GB disk"
echo "   Windows Server: 2 vCPU, 4GB RAM, 60GB disk"
echo "   Kali Linux:     2 vCPU, 4GB RAM, 40GB disk"
echo "=============================================="

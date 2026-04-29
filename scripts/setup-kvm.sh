#!/bin/bash
# setup-kvm.sh — KVM/QEMU virtualisation setup
# Run once after reboot post rpm-ostree install
# Requirements: qemu-kvm, libvirt, virt-manager must be layered via packages.sh first

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-kvm.sh"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   KVM / QEMU — setup                     ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Enable and start libvirtd ────────────────────────────────────────────
run_step "KVM_LIBVIRTD_ENABLED" "Enabling and starting libvirtd" \
    sudo systemctl enable --now libvirtd

# ── Add user to libvirt group ────────────────────────────────────────────
run_step "KVM_USER_GROUP" "Adding user to libvirt group" \
    sudo usermod -aG libvirt "$USER"

# ── Start default NAT network ─────────────────────────────────────────────
echo -e "\n${CYAN}==> Configuring default NAT network...${NC}"
sudo virsh --connect qemu:///system net-autostart default 2>/dev/null || true
sudo virsh --connect qemu:///system net-start default 2>/dev/null \
    && echo -e "${GREEN}✓ Network 'default' started${NC}" \
    || echo -e "${YELLOW}⚠ Network 'default' already active or unavailable${NC}"
step_done "KVM_NETWORK_DEFAULT"

# ── Verify KVM ───────────────────────────────────────────────────────────
echo -e "\n${CYAN}==> Verifying KVM...${NC}"
if ls /dev/kvm &>/dev/null; then
    echo -e "${GREEN}✓ /dev/kvm found — KVM acceleration available${NC}"
    step_done "KVM_DEVICE_OK"
else
    echo -e "${RED}✗ /dev/kvm missing — check BIOS: enable AMD-V / Intel VT-x${NC}"
    step_failed "KVM_DEVICE_OK"
fi

step_done "KVM_SETUP_DONE"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} KVM ready!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " ${YELLOW}NOTE: Log out and back in for group changes to take effect.${NC}"
echo ""
echo -e " Then start virt-manager:  ${CYAN}virt-manager${NC}"
echo ""
echo -e " Recommended VM specs:"
echo -e "   Windows 11:      4 vCPU, 8 GB RAM, 80 GB disk"
echo -e "   Windows Server:  2 vCPU, 4 GB RAM, 60 GB disk"
echo -e "   Kali Linux:      2 vCPU, 4 GB RAM, 40 GB disk"
echo ""

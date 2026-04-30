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

configure_default_network() {
    local network_xml
    network_xml="$(mktemp)"
    trap 'rm -f "$network_xml"' RETURN

    if ip -4 route show 192.168.122.0/24 2>/dev/null | grep -qv 'dev virbr0'; then
        echo -e "${YELLOW}⚠ Existing 192.168.122.0/24 route detected — using 192.168.125.0/24 for libvirt default network${NC}"
        sudo virsh --connect qemu:///system net-destroy default 2>/dev/null || true
        sudo virsh --connect qemu:///system net-undefine default 2>/dev/null || true
        cat > "$network_xml" <<'XML'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.125.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.125.2' end='192.168.125.254'/>
    </dhcp>
  </ip>
</network>
XML
        sudo virsh --connect qemu:///system net-define "$network_xml"
    fi

    sudo virsh --connect qemu:///system net-autostart default 2>/dev/null || true
    sudo virsh --connect qemu:///system net-start default 2>/dev/null \
        && echo -e "${GREEN}✓ Network 'default' started${NC}" \
        || echo -e "${YELLOW}⚠ Network 'default' already active or unavailable${NC}"
}

# ── Enable and start libvirtd ────────────────────────────────────────────
run_step "KVM_LIBVIRTD_ENABLED" "Enabling and starting libvirtd" \
    sudo systemctl enable --now libvirtd

# ── Add user to libvirt group ────────────────────────────────────────────
run_step "KVM_USER_GROUP" "Adding user to libvirt group" \
    sudo usermod -aG libvirt "$USER"

# ── Start default NAT network ─────────────────────────────────────────────
echo -e "\n${CYAN}==> Configuring default NAT network...${NC}"
configure_default_network
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

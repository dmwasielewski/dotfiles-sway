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

KVM_NETWORK_NAME="${KVM_NETWORK_NAME:-dotfiles-nat}"
KVM_BRIDGE_NAME="${KVM_BRIDGE_NAME:-virbr10}"

pick_kvm_subnet() {
    local candidate
    local candidates=("192.168.125" "192.168.126" "192.168.127" "192.168.128")

    for candidate in "${candidates[@]}"; do
        if ! ip -4 route show "${candidate}.0/24" 2>/dev/null | grep -q .; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

configure_repo_network() {
    local network_xml subnet
    network_xml="$(mktemp)"
    trap 'rm -f "$network_xml"' RETURN

    if sudo virsh --connect qemu:///system net-info "$KVM_NETWORK_NAME" >/dev/null 2>&1; then
        echo -e "${YELLOW}==> Network '$KVM_NETWORK_NAME' already defined — reusing existing configuration.${NC}"
    else
        subnet="$(pick_kvm_subnet)" || {
            echo -e "${RED}✗ Could not find a free libvirt NAT subnet for $KVM_NETWORK_NAME.${NC}"
            return 1
        }

        echo -e "${CYAN}==> Defining dedicated libvirt NAT network '$KVM_NETWORK_NAME' on ${subnet}.0/24...${NC}"
        cat > "$network_xml" <<'XML'
<network>
  <name>dotfiles-nat</name>
  <forward mode='nat'/>
  <bridge name='virbr10' stp='on' delay='0'/>
  <ip address='192.168.125.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.125.2' end='192.168.125.254'/>
    </dhcp>
  </ip>
</network>
XML
        sed -i \
            -e "s/dotfiles-nat/$KVM_NETWORK_NAME/g" \
            -e "s/virbr10/$KVM_BRIDGE_NAME/g" \
            -e "s/192.168.125/${subnet}/g" \
            "$network_xml"
        sudo virsh --connect qemu:///system net-define "$network_xml"
    fi

    sudo virsh --connect qemu:///system net-autostart "$KVM_NETWORK_NAME" 2>/dev/null || true
    sudo virsh --connect qemu:///system net-start "$KVM_NETWORK_NAME" 2>/dev/null \
        && echo -e "${GREEN}✓ Network '$KVM_NETWORK_NAME' started${NC}" \
        || echo -e "${YELLOW}⚠ Network '$KVM_NETWORK_NAME' already active or unavailable${NC}"
}

require_sudo_session

# ── Enable and start libvirtd ────────────────────────────────────────────
run_step "KVM_LIBVIRTD_ENABLED" "Enabling and starting libvirtd" \
    sudo systemctl enable --now libvirtd

# ── Add user to libvirt group ────────────────────────────────────────────
run_step "KVM_USER_GROUP" "Adding user to libvirt group" \
    sudo usermod -aG libvirt "$USER"

# ── Start dedicated NAT network ───────────────────────────────────────────
echo -e "\n${CYAN}==> Configuring dedicated libvirt NAT network...${NC}"
configure_repo_network
step_done "KVM_NETWORK_DOTFILES_NAT"

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
echo -e " Use libvirt network:      ${CYAN}${KVM_NETWORK_NAME}${NC}"
echo ""
echo -e " Recommended VM specs:"
echo -e "   Windows 11:      4 vCPU, 8 GB RAM, 80 GB disk"
echo -e "   Windows Server:  2 vCPU, 4 GB RAM, 60 GB disk"
echo -e "   Kali Linux:      2 vCPU, 4 GB RAM, 40 GB disk"
echo ""
print_state_summary

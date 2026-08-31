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
    # Self-clearing: a RETURN trap outlives the function that set it and fires
    # again when the caller returns, with the local variable out of scope — under
    # `set -u` that aborts the run somewhere unrelated. See setup-nordvpn.sh.
    trap 'rm -f "${network_xml:-}"; trap - RETURN' RETURN

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
# On rpm-ostree systems a package-provided group can live only in
# /usr/lib/group, and `usermod -aG` then **exits 0 without doing anything** —
# it edits /etc/group and will not create an entry that is not already there.
# The install therefore recorded KVM_USER_GROUP=done on a machine where the
# group stayed empty (observed 2026-08-31 in the test VM: /etc/group had no
# libvirt line, /usr/lib/group had `libvirt:x:961:`, usermod returned 0, nothing
# changed). This host escaped it only because its libvirt entry predates that
# layout and already sits in /etc/group.
#
# So: materialise the entry in /etc/group first, preserving the GID from the
# package layer, then add the user — and confirm from the resulting state rather
# than from usermod's exit code, which has already proved it can lie here.
add_user_to_libvirt_group() {
    if ! getent group libvirt >/dev/null 2>&1; then
        echo "libvirt group does not exist at all — is libvirt installed?" >&2
        return 1
    fi
    if ! grep -q "^libvirt:" /etc/group; then
        echo "==> libvirt group exists only in the package layer — copying it to /etc/group"
        getent group libvirt | sudo tee -a /etc/group >/dev/null || return 1
    fi
    sudo usermod -aG libvirt "$USER" || return 1
    # The check that actually matters.
    if getent group libvirt | grep -q "\b${USER}\b"; then
        return 0
    fi
    echo "usermod reported success but $USER is still not in the libvirt group." >&2
    return 1
}

run_step "KVM_USER_GROUP" "Adding user to libvirt group" add_user_to_libvirt_group

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

# Aggregate readiness must reflect the real components, not be hardcoded to done.
# /dev/kvm is required for hardware acceleration; without it KVM is not ready.
# (KVM_USER_GROUP and KVM_NETWORK_DOTFILES_NAT use run_step/step_done, which exit
# on failure, so reaching here means they passed — but check them anyway so the
# aggregate stays correct if the flow ever changes.)
if [[ "$(step_get KVM_DEVICE_OK)" == "done" \
   && "$(step_get KVM_USER_GROUP)" == "done" \
   && "$(step_get KVM_NETWORK_DOTFILES_NAT)" == "done" ]]; then
    step_done "KVM_SETUP_DONE"
    KVM_OK=1
else
    step_failed "KVM_SETUP_DONE"
    KVM_OK=0
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$KVM_OK" == "1" ]]; then
    echo -e "${BOLD} KVM ready!${NC}"
else
    echo -e "${BOLD}${RED} KVM setup incomplete — /dev/kvm missing (enable AMD-V / Intel VT-x in BIOS), then re-run.${NC}"
fi
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

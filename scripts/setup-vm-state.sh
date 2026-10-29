#!/usr/bin/env bash
# Configure managed guest save on host shutdown, and restore saved guests at the next host boot.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-vm-state.sh"
require_sudo_session
configure_vm_state() {
    sudo install -d -m 755 /etc/sysconfig || return 1
    if [[ -f /etc/sysconfig/libvirt-guests && ! -f /etc/sysconfig/libvirt-guests.before-dotfiles ]]; then
        sudo cp -a /etc/sysconfig/libvirt-guests /etc/sysconfig/libvirt-guests.before-dotfiles || return 1
    fi
    sudo install -m 644 "$DOTFILES/libvirt/libvirt-guests" /etc/sysconfig/libvirt-guests || return 1
    # Do not restart an active service: its stop action would save running VMs now.
    sudo systemctl enable --now libvirt-guests.service || return 1
    sudo cmp -s "$DOTFILES/libvirt/libvirt-guests" /etc/sysconfig/libvirt-guests || return 1
    sudo systemctl is-enabled --quiet libvirt-guests.service || return 1
    sudo systemctl is-active --quiet libvirt-guests.service || return 1
}
run_step "KVM_GUEST_STATE_SAVE" "Enabling guest state save at host shutdown" configure_vm_state
print_state_summary

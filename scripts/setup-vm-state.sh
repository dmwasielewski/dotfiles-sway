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
    # Shutdown ordering + stop timeout + fallback (see the drop-in's comments).
    # /usr/local is /var/usrlocal on Fedora Atomic, so it is writable and persists.
    sudo install -D -m 755 "$DOTFILES/libvirt/libvirt-guests-fallback.sh" \
        /usr/local/libexec/dotfiles-libvirt-guests-fallback || return 1
    sudo install -D -m 644 "$DOTFILES/libvirt/libvirt-guests-dotfiles.conf" \
        /etc/systemd/system/libvirt-guests.service.d/50-dotfiles.conf || return 1
    # daemon-reload only re-reads unit files; it does not stop or restart the
    # service, so running guests are not saved by this step.
    sudo systemctl daemon-reload || return 1
    # Do not restart an active service: its stop action would save running VMs now.
    sudo systemctl enable --now libvirt-guests.service || return 1
    sudo cmp -s "$DOTFILES/libvirt/libvirt-guests" /etc/sysconfig/libvirt-guests || return 1
    sudo systemctl is-enabled --quiet libvirt-guests.service || return 1
    sudo systemctl is-active --quiet libvirt-guests.service || return 1
    # The merged unit must carry the timeout and the ordering, not just the file.
    [[ "$(systemctl show libvirt-guests.service -p TimeoutStopUSec --value)" != "infinity" ]] || return 1
    local after                          # collected first: grep -q in a pipe + pipefail can SIGPIPE
    after="$(systemctl show libvirt-guests.service -p After --value)"
    [[ " $after " == *" libvirtd.service "* ]] || return 1
}
run_step "KVM_GUEST_STATE_SAVE" "Enabling guest state save at host shutdown" configure_vm_state
print_state_summary

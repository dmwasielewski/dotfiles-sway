#!/usr/bin/env bash
# Start the personal Windows VM and open its console in Sway workspace 6.
set -euo pipefail
export LC_ALL=C
VM=win11edu-damian
URI=qemu:///system
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-vm"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
LOG="$STATE_DIR/$VM.log"
touch "$LOG"
chmod 600 "$LOG"
exec >>"$LOG" 2>&1
printf '\n[%s] Windows session launcher\n' "$(date -Is)"
# Hold this lock for the viewer lifetime: repeated shortcuts cannot open copies.
exec 9>"${XDG_RUNTIME_DIR:?A graphical user session is required}/$VM-viewer.lock"
flock -n 9 || exit 0

# Allow the host libvirt socket to become ready after login.
READY=false
for ((attempt=0; attempt<30; attempt++)); do
    if virsh --connect "$URI" list --all --name >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 1
done
if ! $READY; then
    echo 'Host libvirt did not become ready; run setup-kvm.sh after reboot.'
    exit 1
fi
if ! STATE=$(virsh --connect "$URI" domstate "$VM" 2>/dev/null); then
    # A fresh install does not contain the personal VM until explicitly restored.
    echo 'Personal Windows VM is not defined; skipping automatic startup.'
    exit 0
fi
case "$STATE" in
    'shut off') virsh --connect "$URI" start "$VM" ;;
    running|paused|'in shutdown') ;;
    *) echo "Unsupported VM state: $STATE"; exit 1 ;;
esac
exec virt-viewer --attach --connect "$URI" --wait --reconnect --hotkeys=release-cursor=ctrl+alt --domain-name "$VM"

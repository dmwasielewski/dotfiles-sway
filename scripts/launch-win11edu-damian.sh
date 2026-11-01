#!/usr/bin/env bash
# Open the personal Windows VM's console in Sway workspace 6.
#
#   launch-win11edu-damian.sh             start the VM if it is off, open console
#   launch-win11edu-damian.sh --no-start  open the console only (used at login)
#
# Since 2026-11-01 the login path uses --no-start: Windows costs ~18 W on battery
# (measured 27 W with it vs 8.7 W without), so it is started by hand with the
# console's Run button. A state saved at host shutdown is kept and restored on
# that start (libvirt resumes a managed-save image instead of a cold boot).
set -euo pipefail
NO_START=false
[[ "${1:-}" == "--no-start" ]] && NO_START=true
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
# Serialize launch requests. virt-manager reuses its existing per-domain window.
exec 9>"${XDG_RUNTIME_DIR:?A graphical user session is required}/$VM-launcher.lock"
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
    'shut off')
        if $NO_START; then
            echo 'Console only (--no-start): Windows stays off until started by hand.'
        else
            virsh --connect "$URI" start "$VM"
        fi
        ;;
    running|paused|'in shutdown') ;;
    *) echo "Unsupported VM state: $STATE"; exit 1 ;;
esac
exec virt-manager --connect "$URI" --show-domain-console "$VM"

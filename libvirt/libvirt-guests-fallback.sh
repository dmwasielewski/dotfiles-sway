#!/bin/bash
# ExecStopPost for libvirt-guests.service (installed by scripts/setup-vm-state.sh
# as /usr/local/libexec/dotfiles-libvirt-guests-fallback).
#
# Normal path: libvirt-guests saves every running guest (managedsave, ~4–7 s
# measured for win11edu-damian) and this script does nothing.
#
# Failure path: on 2026-10-30 one managedsave hung for over 8 minutes while the
# unit had no stop timeout, so the laptop could only be powered off by hand. The
# drop-in now gives libvirt-guests a stop timeout; when it fires (or the stop
# fails), systemd still runs this ExecStopPost with SERVICE_RESULT != success.
# For every guest still running it then:
#   1. aborts the stuck save job,
#   2. asks the guest to shut down cleanly (ACPI) and waits,
#   3. only if it is still running, powers it off (like pulling the plug).
# The host shutdown then continues instead of hanging. The guest's RAM state is
# lost in this path, which is the same outcome as the hang ending in a forced
# power-off, minus the hang.
set -uo pipefail

RESULT="${SERVICE_RESULT:-success}"
URIS="${URIS:-qemu:///system}"           # same variable as /etc/sysconfig/libvirt-guests
WAIT="${FALLBACK_SHUTDOWN_WAIT:-90}"     # seconds for a clean guest shutdown
POLL="${FALLBACK_POLL:-2}"

log() { echo "dotfiles-libvirt-guests-fallback: $*"; }

if [[ "$RESULT" == "success" ]]; then
    exit 0
fi
log "libvirt-guests stop ended with '$RESULT' — handling guests that are still running"

for uri in $URIS; do
    mapfile -t running < <(virsh -c "$uri" list --name --state-running 2>/dev/null | sed '/^$/d')
    [[ ${#running[@]} -eq 0 ]] && { log "$uri: no running guests"; continue; }

    for dom in "${running[@]}"; do
        log "$uri: $dom — aborting the pending save job"
        virsh -c "$uri" domjobabort "$dom" >/dev/null 2>&1 || true
        log "$uri: $dom — requesting a clean shutdown (up to ${WAIT}s)"
        virsh -c "$uri" shutdown "$dom" >/dev/null 2>&1 || true
    done

    deadline=$(( SECONDS + WAIT ))
    while (( SECONDS < deadline )); do
        still=0
        for dom in "${running[@]}"; do
            [[ "$(virsh -c "$uri" domstate "$dom" 2>/dev/null | head -1)" == "running" ]] && still=1
        done
        (( still )) || break
        sleep "$POLL"
    done

    for dom in "${running[@]}"; do
        if [[ "$(virsh -c "$uri" domstate "$dom" 2>/dev/null | head -1)" == "running" ]]; then
            log "$uri: $dom — still running after ${WAIT}s, powering it off"
            virsh -c "$uri" destroy "$dom" >/dev/null 2>&1 || true
        else
            log "$uri: $dom — shut down cleanly"
        fi
    done
done
exit 0

#!/bin/bash
# backup-win11.sh — snapshot/restore Windows 11 VM for SOC lab testing
# Usage: bash backup-win11.sh           → create snapshot
#        bash backup-win11.sh restore   → restore last snapshot
set -euo pipefail

VM="win11"
CONNECT="qemu:///system"
SNAP_NAME="${2:-clean-baseline}"

if [[ "${1:-snapshot}" == "restore" ]]; then
    echo "==> Restoring Windows 11 VM to snapshot '${SNAP_NAME}'..."
    virsh --connect "$CONNECT" snapshot-revert "$VM" --snapshotname "$SNAP_NAME"
    echo "==> Restored. Start VM: virsh --connect $CONNECT start $VM"
else
    TAG="$(date +%Y%m%d-%H%M)"
    echo "==> Creating snapshot of Windows 11 VM: ${SNAP_NAME}-${TAG}..."
    virsh --connect "$CONNECT" snapshot-create-as "$VM" \
        --name "${SNAP_NAME}-${TAG}" \
        --description "SOC lab snapshot ${TAG}"
    echo "==> Snapshot created."
    echo ""
    echo "    List snapshots:  virsh --connect $CONNECT snapshot-list $VM"
    echo "    Restore latest:  bash $0 restore ${SNAP_NAME}-${TAG}"
fi

#!/bin/bash
# backup-container.sh — snapshot a distrobox/toolbox container so you can restore it later.
# Usage: bash ~/dotfiles-sway/scripts/backup-container.sh [container-name]
#   container-name defaults to "security"
# Creates a podman image: localhost/<name>-backup:<date>
set -euo pipefail

CONTAINER="${1:-security}"
TAG="${2:-$(date +%Y%m%d)}"
IMAGE="localhost/${CONTAINER}-backup:${TAG}"

echo "==> Creating snapshot of '$CONTAINER' as '$IMAGE'..."

if ! podman container inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERROR: container '$CONTAINER' not found."
    echo "       Running containers:"
    podman ps --format '{{.Names}}'
    exit 1
fi

podman commit "$CONTAINER" "$IMAGE"

echo ""
echo "==> Snapshot created: $IMAGE"
echo ""
echo "    Restore as a new container:"
echo "      distrobox create -i $IMAGE -n ${CONTAINER}-fresh"
echo ""
echo "    List all backups:"
echo "      podman images | grep ${CONTAINER}-backup"
echo ""
echo "    Delete old backup:"
echo "      podman rmi ${IMAGE}"

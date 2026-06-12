#!/bin/bash
# Clone an unlocked vault onto a second freshly-set-up LUKS USB (offline backup).
# Both must already be unlocked+mounted (vault unlock on source; setup+open dest).
# Usage: clone-vault.sh <src-mount> <dest-mount>
set -euo pipefail
src="${1:?src mount}"; dest="${2:?dest mount}"
mountpoint -q "$src"  || { echo "src not mounted: $src" >&2; exit 1; }
mountpoint -q "$dest" || { echo "dest not mounted: $dest" >&2; exit 1; }
rsync -aH --delete "$src"/ "$dest"/
echo "vault: cloned $src -> $dest"

#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == --autostart ]]; then
    # A fresh install must not open a login wizard unattended.
    [[ -s "$HOME/.config/onedrive-gui/profiles" ]] || exit 0
    shift
fi
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "${XDG_RUNTIME_DIR:-/tmp}/onedrive-gui-$UID"
exec flock -n "${XDG_RUNTIME_DIR:-/tmp}/onedrive-gui-$UID/gui.lock" \
    "$HOME/.local/opt/onedrive-gui/current/AppRun" "$@"

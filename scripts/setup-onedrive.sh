#!/bin/bash
# Compatibility entrypoint for the former full-sync installer.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
exec bash "$DOTFILES/scripts/setup-onedriver.sh" "$@"

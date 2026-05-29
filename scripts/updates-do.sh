#!/bin/bash
# updates-do.sh — launcher: opens the interactive update menu in a foot terminal.
# The actual menu logic lives in updates-menu.sh (so it can use a real script,
# not a fragile inline heredoc).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec foot --title "system-updates" -- bash "$SCRIPT_DIR/updates-menu.sh"

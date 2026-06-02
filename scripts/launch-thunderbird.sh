#!/bin/bash
# Launch the installed Thunderbird flatpak, discovered at runtime (see
# thunderbird-id.sh) so a Flathub variant rebase (regular <-> _esr) never breaks
# autostart again. Does nothing if Thunderbird is not installed.
set -uo pipefail

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
id="$("$DIR/thunderbird-id.sh")"

[[ -n "$id" ]] && exec flatpak run "$id"

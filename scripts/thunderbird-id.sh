#!/bin/bash
# Print the app ID of the installed Thunderbird flatpak, discovered at runtime.
# Flathub deprecated the plain `org.mozilla.Thunderbird` ID and rebased it to
# `org.mozilla.thunderbird_esr`, so nothing should hardcode it. Prefers the
# regular (feature) release over the ESR variant; prints nothing (exit 0) when no
# Thunderbird flatpak is installed. Host context (bare `flatpak`).
# Usage:  id="$(scripts/thunderbird-id.sh)"
set -uo pipefail

_tb_list() {
    flatpak list --app --columns=application 2>/dev/null | grep -iE '^org\.mozilla\.thunderbird'
}

id="$(_tb_list | grep -vi esr | head -n1)"   # prefer the regular (feature) release
[ -z "$id" ] && id="$(_tb_list | head -n1)"   # otherwise whatever variant is installed

[ -n "$id" ] && printf '%s\n' "$id"
exit 0

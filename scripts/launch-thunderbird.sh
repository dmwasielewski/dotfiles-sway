#!/bin/bash
# Launch whichever Thunderbird flatpak is installed, discovered at runtime so a
# change of variant (regular <-> ESR) never breaks autostart again — no hardcoded
# app ID. Prefers the regular feature release over the ESR variant when both are
# installed; falls back to ESR; does nothing if Thunderbird is not installed.
set -uo pipefail

list_tb() {
    flatpak list --app --columns=application 2>/dev/null \
        | grep -iE '^org\.mozilla\.thunderbird'
}

id="$(list_tb | grep -vi esr | head -n1)"   # prefer the regular (feature) release
[[ -z "$id" ]] && id="$(list_tb | head -n1)" # otherwise whatever is installed (ESR)

[[ -n "$id" ]] && exec flatpak run "$id"

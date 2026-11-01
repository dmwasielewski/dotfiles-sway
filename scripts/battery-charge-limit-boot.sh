#!/bin/bash
# Boot-time apply of the battery charge limit (installed by
# setup-battery-charge-limit.sh as /usr/local/libexec/dotfiles-battery-charge-limit-boot
# and run as root by dotfiles-battery-charge-limit.service).
#
# Why: ASUS firmware resets charge_control_end_threshold to 100 % at every power-on
# (ASUS FAQ 1032726). The Waybar module re-applies the saved choice only after
# login, so the battery kept charging between boot and login — measured 2026-11-01:
# 80 % → 87 % across a reboot that waited 10 min at the LUKS prompt. While the
# laptop is powered off the limit held (8 % → 79/80 % over 46 h on the charger).
#
# This runs right after the filesystems are mounted (~1 s after the LUKS unlock),
# so only the time spent at the disk passphrase prompt remains uncovered: the
# saved choice lives on the encrypted disk and cannot be read before it is unlocked.
#
# The choice is per user (~/.config/dotfiles/battery-charge-limit, written by the
# Waybar toggle). Homes are discovered from the passwd database; if several users
# saved one, the most recently changed file wins. No file → the tool's default.
set -uo pipefail

TOOL="${BATTERY_LIMIT_TOOL:-/usr/local/libexec/dotfiles-battery-charge-limit}"
REL=".config/dotfiles/battery-charge-limit"

newest="" newest_mtime=0
while IFS=: read -r _ _ uid _ _ home _; do
    (( uid >= 1000 && uid < 65534 )) || continue
    f="$home/$REL"
    [[ -f "$f" ]] || continue
    m="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    (( m > newest_mtime )) && { newest="$f"; newest_mtime="$m"; }
done < <(${BATTERY_PASSWD_CMD:-getent passwd})

if [[ -n "$newest" ]]; then
    cfg_home="${newest%/dotfiles/battery-charge-limit}"   # …/.config
    echo "battery charge limit: applying the choice saved in $newest"
    XDG_CONFIG_HOME="$cfg_home" "$TOOL" apply
else
    echo "battery charge limit: no saved choice found — applying the default"
    XDG_CONFIG_HOME="/nonexistent" "$TOOL" apply
fi

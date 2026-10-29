#!/bin/bash
# Install the battery charge-limit toggle (Waybar battery icon, 80 % / 100 %).
#
#   setup-battery-charge-limit.sh          install (needs sudo once)
#   setup-battery-charge-limit.sh --check  read-only check, no sudo
#
# Installs the udev rule that makes charge_control_end_threshold writable for
# `wheel`, links the toggle into ~/.local/bin and applies the saved limit
# (80 % by default). Hardware without the attribute (desktops, VMs, batteries
# whose driver exposes no limit) is a clean skip, not a failure.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
RULE_SRC="$DOTFILES/udev/90-dotfiles-battery-charge-limit.rules"
RULE_DST="/etc/udev/rules.d/$(basename "$RULE_SRC")"
TOOL="$DOTFILES/scripts/battery-charge-limit.sh"
LINK="$HOME/.local/bin/battery-charge-limit"
GROUP="wheel"                            # must match the rule file

attr() {                                 # first battery's limit attribute, if any
    local d
    for d in /sys/class/power_supply/*; do
        [[ "$(cat "$d/type" 2>/dev/null)" == "Battery" && -e "$d/charge_control_end_threshold" ]] &&
            { printf '%s\n' "$d/charge_control_end_threshold"; return 0; }
    done
    return 1
}

ATTR="$(attr || true)"

if [[ "${1:-}" == "--check" ]]; then
    [[ -z "$ATTR" ]] && { echo "battery charge limit: not supported on this hardware — skipped"; exit 0; }
    ok=0
    cmp -s "$RULE_SRC" "$RULE_DST" || { echo "missing/outdated $RULE_DST"; ok=1; }
    [[ -w "$ATTR" ]] || { echo "$ATTR not writable by $USER"; ok=1; }
    [[ "$(readlink -f "$LINK" 2>/dev/null)" == "$(readlink -f "$TOOL")" ]] || { echo "missing $LINK"; ok=1; }
    exit "$ok"
fi

mkdir -p "$(dirname "$LINK")"
ln -sfn "$TOOL" "$LINK"
chmod +x "$TOOL"

if [[ -z "$ATTR" ]]; then
    echo "==> No battery with a charge limit on this hardware — nothing else to do."
    exit 0
fi

if ! id -nG | tr ' ' '\n' | grep -qx "$GROUP"; then
    echo "ERROR: $USER is not in '$GROUP'; the udev rule grants access to that group only." >&2
    exit 1
fi

if ! cmp -s "$RULE_SRC" "$RULE_DST"; then
    echo "==> Installing $RULE_DST (sudo)"
    sudo install -m 0644 "$RULE_SRC" "$RULE_DST"
    sudo udevadm control --reload
fi
sudo udevadm trigger --subsystem-match=power_supply --action=change
sudo udevadm settle

if [[ ! -w "$ATTR" ]]; then
    echo "ERROR: $ATTR is still not writable after the udev rule ran:" >&2
    ls -l "$ATTR" >&2
    exit 1
fi

"$LINK" apply
echo "==> Charge limit: $(cat "$ATTR")%  (click the Waybar battery icon to switch 80/100)"
# Reload Waybar's config so a first install swaps in the new module at once.
pkill -SIGUSR2 -x waybar 2>/dev/null || true

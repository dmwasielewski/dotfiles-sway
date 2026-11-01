#!/bin/bash
# Install the battery charge-limit toggle (Waybar battery icon, 80 % / 100 %).
#
#   setup-battery-charge-limit.sh          install (needs sudo once)
#   setup-battery-charge-limit.sh --check  read-only check, no sudo
#
# Installs the udev rule that makes charge_control_end_threshold writable for
# `wheel`, links the toggle into ~/.local/bin, installs a boot service that
# re-applies the saved limit before login (ASUS firmware resets it to 100 % at
# every power-on), and applies the saved limit now (80 % by default). Hardware without the attribute (desktops, VMs, batteries
# whose driver exposes no limit) is a clean skip, not a failure.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
RULE_SRC="$DOTFILES/udev/90-dotfiles-battery-charge-limit.rules"
RULE_DST="/etc/udev/rules.d/$(basename "$RULE_SRC")"
TOOL="$DOTFILES/scripts/battery-charge-limit.sh"
LINK="$HOME/.local/bin/battery-charge-limit"
GROUP="wheel"                            # must match the rule file
# Boot-time apply (root, before login): a copy of the tool, a wrapper, a unit.
SYS_TOOL="/usr/local/libexec/dotfiles-battery-charge-limit"
BOOT_SRC="$DOTFILES/scripts/battery-charge-limit-boot.sh"
BOOT_DST="/usr/local/libexec/dotfiles-battery-charge-limit-boot"
UNIT_SRC="$DOTFILES/systemd/dotfiles-battery-charge-limit.service"
UNIT_DST="/etc/systemd/system/$(basename "$UNIT_SRC")"
boot_ok() {
    cmp -s "$TOOL" "$SYS_TOOL" && cmp -s "$BOOT_SRC" "$BOOT_DST" && cmp -s "$UNIT_SRC" "$UNIT_DST" &&
        systemctl is-enabled --quiet "$(basename "$UNIT_SRC")" 2>/dev/null
}

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
    boot_ok || { echo "boot-time apply service missing/outdated ($UNIT_DST)"; ok=1; }
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

# Already installed and in effect: nothing needs root, so never ask for a
# password (re-running this from a non-interactive shell must not fail).
if cmp -s "$RULE_SRC" "$RULE_DST" && [[ -w "$ATTR" ]]; then
    echo "==> udev rule already installed and active — no sudo needed"
else
    if ! cmp -s "$RULE_SRC" "$RULE_DST"; then
        echo "==> Installing $RULE_DST (sudo)"
        sudo install -m 0644 "$RULE_SRC" "$RULE_DST"
        sudo udevadm control --reload
    fi
    sudo udevadm trigger --subsystem-match=power_supply --action=change
    sudo udevadm settle
fi

if boot_ok; then
    echo "==> boot-time apply service already installed — no sudo needed"
else
    echo "==> Installing the boot-time apply service (sudo)"
    # /usr/local is /var/usrlocal on Fedora Atomic: writable and persistent.
    sudo install -D -m 0755 "$TOOL" "$SYS_TOOL"
    sudo install -D -m 0755 "$BOOT_SRC" "$BOOT_DST"
    sudo install -m 0644 "$UNIT_SRC" "$UNIT_DST"
    sudo systemctl daemon-reload
    # --now runs it once, which proves the root path works before the next boot.
    sudo systemctl enable --now "$(basename "$UNIT_SRC")"
fi

if [[ ! -w "$ATTR" ]]; then
    echo "ERROR: $ATTR is still not writable after the udev rule ran:" >&2
    ls -l "$ATTR" >&2
    exit 1
fi

"$LINK" apply
echo "==> Charge limit: $(cat "$ATTR")%  (click the Waybar battery icon to switch 80/100)"
# Reload Waybar's config so a first install swaps in the new module at once.
pkill -SIGUSR2 -x waybar 2>/dev/null || true

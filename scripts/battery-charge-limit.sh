#!/bin/bash
# Battery charge limit — Waybar module + toggle, like MyASUS "Battery Care".
#
#   battery-charge-limit status   Waybar JSON (text, tooltip, class)
#   battery-charge-limit toggle   switch between CARE (80 %) and FULL (100 %)
#   battery-charge-limit apply    write the saved choice to the firmware
#
# The laptop lives on AC, so by default it stops charging at 80 % (the cell ages
# far slower than when held full and warm). Before a day away from the charger
# one click selects 100 %; the icon turns warning-amber while that is active, as
# a reminder to switch back.
#
# The kernel exposes the limit as charge_control_end_threshold on the battery
# (on ASUS via the asus-wmi battery hook). It is root-owned; the udev rule
# installed by setup-battery-charge-limit.sh makes it group-writable for wheel,
# so no click ever asks for a password. The choice is saved in the user config
# and re-applied by `status` whenever the firmware value drifts from it (boot,
# resume — some firmware resets the limit), so the mode survives restarts.
#
# Nothing is reported that was not read back: after every write sysfs is read
# again, and a refused write is shown as a failure, never as the new mode.
set -uo pipefail

SYSFS="${BATTERY_SYSFS_ROOT:-/sys}"
STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/battery-charge-limit"
CARE=80
FULL=100
SIGNAL="${BATTERY_WAYBAR_SIGNAL:-9}"     # matches "signal" in waybar/config; 0 = none

# ── Discovery (never hardcode BAT0/AC0) ──────────────────────────────────────
find_battery() {                          # prints the first battery directory
    local d
    for d in "$SYSFS"/class/power_supply/*; do
        [[ "$(cat "$d/type" 2>/dev/null)" == "Battery" ]] && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}
on_ac() {                                 # 0 if any mains supply is online
    local d
    for d in "$SYSFS"/class/power_supply/*; do
        [[ "$(cat "$d/type" 2>/dev/null)" == "Mains" && "$(cat "$d/online" 2>/dev/null)" == "1" ]] && return 0
    done
    return 1
}

BAT="$(find_battery || true)"
ATTR="${BAT:+$BAT/charge_control_end_threshold}"

supported() { [[ -n "$BAT" && -e "$ATTR" ]]; }
current_limit() { cat "$ATTR" 2>/dev/null; }
saved_limit() {
    local v
    v="$(cat "$STATE_FILE" 2>/dev/null || true)"
    [[ "$v" == "$CARE" || "$v" == "$FULL" ]] && printf '%s' "$v" || printf '%s' "$CARE"
}

# Write and read back. Succeeds only if the firmware now reports the value.
write_limit() {                           # $1 = value
    [[ -w "$ATTR" ]] || return 1
    printf '%s' "$1" > "$ATTR" 2>/dev/null || return 1
    [[ "$(current_limit)" == "$1" ]]
}

# One writer at a time. Without this, Waybar's 5-second `status` (which re-applies
# the saved choice) could run between toggle's write and its save, see the new
# value as "drift" and put the old one back — observed live on 2026-10-29.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/battery-charge-limit.lock"
lock() { exec 9>"$LOCK" && flock "$@" 9; }   # lock -n = give up if busy

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a "Battery" "$1" "${2:-}" || true; }
redraw() { [[ "$SIGNAL" != 0 ]] && pkill -RTMIN+"$SIGNAL" -x waybar 2>/dev/null || true; }

# ── status ───────────────────────────────────────────────────────────────────
json_escape() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "${s//$'\n'/\\n}"; }

hm() {                                    # $1 = hours as "H.hh" → "Hh MMm"
    awk -v h="$1" 'BEGIN { m = int(h * 60 + 0.5); printf "%dh %02dm", m / 60, m % 60 }'
}

cmd_status() {
    if [[ -z "$BAT" ]]; then
        printf '{"text":"","tooltip":"","class":"none"}\n'   # empty text hides the module
        return 0
    fi

    local cap status icon classes=() lines=() limit="" saved
    cap="$(cat "$BAT/capacity" 2>/dev/null || echo 0)"
    status="$(cat "$BAT/status" 2>/dev/null || echo Unknown)"

    # Self-heal: firmware (boot, resume) may have reset the limit. Skipped while
    # a toggle holds the lock — its half-done state is not drift.
    if supported; then
        if lock -n; then
            saved="$(saved_limit)"
            limit="$(current_limit)"
            if [[ "$limit" != "$saved" && -w "$ATTR" ]]; then
                write_limit "$saved" || true
                limit="$(current_limit)"
            fi
            flock -u 9
        fi
        saved="$(saved_limit)"
        limit="$(current_limit)"
    fi

    # Same glyphs and states as the built-in Waybar battery module it replaces.
    local icons=($'' $'' $'' $'' $'')
    if [[ "$status" == "Charging" ]]; then
        icon=$''; classes+=(charging)
    elif on_ac; then
        icon=$''; classes+=(plugged)
    else
        icon="${icons[$(( cap >= 100 ? 4 : cap * 5 / 100 ))]}"
    fi
    [[ "$status" == "Full" ]] && classes+=(full)
    (( cap <= 40 )) && classes+=(warning)
    (( cap <= 20 )) && classes+=(critical)

    # Colour rule (Damian, 2026-10-29), on AC only:
    #   charging                         -> green  (.charging)
    #   not charging, above ${CARE} %    -> amber  (.above-care) — in either mode:
    #     a full battery after 100 % mode, or one still above 80 % in 80 % mode
    #   not charging, at/below ${CARE} % -> neutral bar colour
    # Off AC the usual warning/critical levels apply and no amber is added.
    if [[ "$status" != "Charging" ]] && on_ac && (( cap > CARE )); then
        classes+=(above-care)
    fi

    if supported; then
        if [[ "$limit" == "$FULL" ]]; then
            lines+=("Charge limit: ${FULL}% (full charge) — click for ${CARE}% (battery care)")
        elif [[ "$limit" == "$CARE" ]]; then
            lines+=("Charge limit: ${CARE}% (battery care) — click for ${FULL}% (full charge)")
        else
            lines+=("Charge limit: ${limit:-unknown}% — click to set ${FULL}%")
        fi
        [[ "$limit" != "$(saved_limit)" ]] &&
            lines+=("⚠ Could not apply the saved ${saved}% limit — run setup-battery-charge-limit.sh")
        [[ -w "$ATTR" ]] ||
            lines+=("⚠ Limit is read-only for this user — run setup-battery-charge-limit.sh")
    else
        lines+=("Charge limit: not supported by this battery")
    fi

    local st="${status,,}"; [[ "$status" == "Not charging" ]] && st="not charging (limit reached)"
    lines+=("Battery: ${cap}%, ${st}$(on_ac && echo ', on AC')")

    # Time estimate from energy and power, when the battery reports them.
    local now full power
    now="$(cat "$BAT/energy_now" 2>/dev/null || echo 0)"
    full="$(cat "$BAT/energy_full" 2>/dev/null || echo 0)"
    power="$(cat "$BAT/power_now" 2>/dev/null || echo 0)"
    if (( power > 0 )); then
        if [[ "$status" == "Discharging" ]]; then
            lines+=("Time left: $(hm "$(awk -v n="$now" -v p="$power" 'BEGIN{print n/p}')")")
        elif [[ "$status" == "Charging" && -n "$limit" ]]; then
            lines+=("Time to ${limit}%: $(hm "$(awk -v f="$full" -v l="$limit" -v n="$now" -v p="$power" \
                'BEGIN{t=(f*l/100-n)/p; print (t>0?t:0)}')")")
        fi
    fi
    local design
    design="$(cat "$BAT/energy_full_design" 2>/dev/null || echo 0)"
    (( design > 0 && full > 0 )) &&
        lines+=("Health: $(awk -v f="$full" -v d="$design" 'BEGIN{printf "%.1f / %.1f Wh (%d%%)", f/1e6, d/1e6, f*100/d}')")

    local tooltip; tooltip="$(printf '%s\n' "${lines[@]}")"; tooltip="${tooltip%$'\n'}"
    local cls; cls="$(printf '"%s",' "${classes[@]}")"
    printf '{"text":"%s","tooltip":"%s","class":[%s],"percentage":%d}\n' \
        "$(json_escape "${cap}% ${icon}")" "$(json_escape "$tooltip")" "${cls%,}" "$cap"
}

# ── toggle / apply ───────────────────────────────────────────────────────────
save() { mkdir -p "$(dirname "$STATE_FILE")" && printf '%s\n' "$1" > "$STATE_FILE"; }

cmd_toggle() {
    supported || { notify "Charge limit not supported" "This battery has no charge_control_end_threshold."; return 1; }
    local cur new
    lock                                  # released when this process exits
    cur="$(current_limit)"
    [[ "$cur" == "$FULL" ]] && new="$CARE" || new="$FULL"
    if write_limit "$new"; then
        save "$new"
        redraw
        return 0
    fi
    # Mode and colour stay as they are: the firmware did not take the value.
    notify "Charge limit NOT changed" "Still ${cur}%. Run: bash ~/dotfiles-sway/scripts/setup-battery-charge-limit.sh"
    redraw
    return 1
}

cmd_apply() {
    supported || return 0                 # nothing to do on hardware without the knob
    local want; lock; want="$(saved_limit)"
    [[ "$(current_limit)" == "$want" ]] && return 0
    write_limit "$want"
}

case "${1:-status}" in
    status) cmd_status ;;
    toggle) cmd_toggle ;;
    apply)  cmd_apply ;;
    *) echo "usage: $(basename "$0") status|toggle|apply" >&2; exit 2 ;;
esac

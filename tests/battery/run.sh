#!/bin/bash
# Tests for scripts/battery-charge-limit.sh against a fake sysfs tree.
# No real battery, Waybar or notification daemon is touched.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../updates/assert.sh
assert_absent() { # $1 haystack $2 needle $3 msg
    if [[ "$1" != *"$2"* ]]; then ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: ${3:-}"
    else ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: ${3:-} ([$1] contains [$2])"; fi
}
SCRIPT="$(cd ../.. && pwd)/scripts/battery-charge-limit.sh"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
printf '#!/bin/bash\nexit 0\n' > "$root/bin/notify-send"
printf '#!/bin/bash\nexit 0\n' > "$root/bin/pkill"
chmod +x "$root/bin"/*
export PATH="$root/bin:$PATH" BATTERY_WAYBAR_SIGNAL=0

# fixture <name> <capacity> <status> <ac-online> [limit|none]
fixture() {
    local t="$root/$1" ps
    rm -rf "$t"; ps="$t/sys/class/power_supply"
    mkdir -p "$ps/BATX" "$ps/ACX" "$t/config"
    echo Battery > "$ps/BATX/type"; echo "$2" > "$ps/BATX/capacity"; echo "$3" > "$ps/BATX/status"
    echo 37000000 > "$ps/BATX/energy_now"; echo 37000000 > "$ps/BATX/energy_full"
    echo 70000000 > "$ps/BATX/energy_full_design"; echo 0 > "$ps/BATX/power_now"
    echo Mains > "$ps/ACX/type"; echo "$4" > "$ps/ACX/online"
    [[ "${5:-80}" != none ]] && printf '%s' "${5:-80}" > "$ps/BATX/charge_control_end_threshold"
    export BATTERY_SYSFS_ROOT="$t/sys" XDG_CONFIG_HOME="$t/config"
    ATTR="$ps/BATX/charge_control_end_threshold"
}
run() { bash "$SCRIPT" "$@"; }
choose() { mkdir -p "$XDG_CONFIG_HOME/dotfiles"; printf '%s\n' "$1" > "$XDG_CONFIG_HOME/dotfiles/battery-charge-limit"; }
valid_json() { python3 -I -c 'import json,sys; json.load(sys.stdin)' <<< "$1"; }

echo "== status: care mode on AC =="
fixture a 100 "Not charging" 1 80
out="$(run status)"
valid_json "$out"; assert_rc $? 0 "status is valid JSON"
assert_contains "$out" '"plugged"' "plugged class on AC"
assert_contains "$out" 'battery care' "tooltip names care mode"
assert_contains "$out" '"above-care"' "amber: 80 % mode but battery still at 100 %"
assert_contains "$out" 'Health: 37.0 / 70.0 Wh (52%)' "health line from energy values"

echo "== status: full mode is amber =="
fixture b 100 "Not charging" 1 100
choose 100
out="$(run status)"
assert_contains "$out" '"above-care"' "amber: full after 100 % mode"
assert_contains "$out" 'full charge) — click for 80%' "tooltip offers switch back"

echo "== status: charging towards 100 % is green, not amber =="
fixture b2 85 Charging 1 100
choose 100
out="$(run status)"
assert_contains "$out" '"charging"' "charging class while charging"
assert_absent "$out" 'above-care' "no amber while still charging"

echo "== status: 80 % mode at 80 % on AC is neutral =="
fixture b3 80 "Not charging" 1 80
out="$(run status)"
assert_absent "$out" 'above-care' "grey once down to the 80 % limit"
assert_absent "$out" '"charging"' "not green when not charging"

echo "== status: on AC above the limit, firmware discharges to it =="
fixture b5 93 Discharging 1 80
choose 80
out="$(run status)"
assert_contains "$out" '"above-care"' "amber while draining to the limit"
assert_absent "$out" '"charging"' "not green: it is not charging"
assert_contains "$out" 'running on battery down to the 80% limit' "tooltip explains the drain"

echo "== status: off AC above 80 % is not amber =="
fixture b4 95 Discharging 0 80
out="$(run status)"
assert_absent "$out" 'above-care' "no amber on battery power"

echo "== status: critical keeps its class alongside full mode =="
fixture c 15 Discharging 0 100
choose 100
out="$(run status)"
assert_contains "$out" '"critical"' "critical class below 20 %"
assert_contains "$out" '"warning"' "warning class below 40 %"
assert_absent "$out" '"plugged"' "not plugged when AC offline"

echo "== toggle: 80 -> 100 -> 80, saved and read back =="
fixture d 70 Charging 1 80
run toggle; assert_rc $? 0 "toggle to 100 succeeds"
assert_eq "$(cat "$ATTR")" 100 "firmware value is 100"
assert_eq "$(cat "$XDG_CONFIG_HOME/dotfiles/battery-charge-limit")" 100 "choice saved"
run toggle; assert_rc $? 0 "toggle back succeeds"
assert_eq "$(cat "$ATTR")" 80 "firmware value is 80"

echo "== toggle: refused write is reported, nothing saved =="
fixture e 70 Charging 1 80
chmod a-w "$ATTR"
run toggle; assert_rc $? 1 "toggle fails on read-only attribute"
assert_eq "$(cat "$ATTR")" 80 "value unchanged"
saved_exists=no; [[ -e "$XDG_CONFIG_HOME/dotfiles/battery-charge-limit" ]] && saved_exists=yes
assert_eq "$saved_exists" no "no choice saved after failure"
out="$(run status)"
assert_contains "$out" 'read-only for this user' "status explains the missing permission"

echo "== status: self-heals a firmware reset =="
fixture f 90 "Not charging" 1 100          # firmware came back at 100
choose 80
run status >/dev/null
assert_eq "$(cat "$ATTR")" 80 "saved 80 % re-applied"

echo "== status: no self-heal while a toggle holds the lock =="
fixture f2 90 "Not charging" 1 100        # toggle wrote 100 but has not saved yet
choose 80
export XDG_RUNTIME_DIR="$root/f2"
( exec 9>"$XDG_RUNTIME_DIR/battery-charge-limit.lock"; flock 9; sleep 2 ) &
sleep 0.3
run status >/dev/null
assert_eq "$(cat "$ATTR")" 100 "status leaves the in-flight value alone"
wait

echo "== status: first run defaults to 80 % =="
fixture g 100 "Not charging" 1 100
run status >/dev/null
assert_eq "$(cat "$ATTR")" 80 "default care limit applied"

echo "== no limit attribute: plain battery, toggle refuses =="
fixture h 60 Discharging 0 none
out="$(run status)"
valid_json "$out"; assert_rc $? 0 "valid JSON without the attribute"
assert_contains "$out" 'not supported' "tooltip says unsupported"
run toggle; assert_rc $? 1 "toggle refuses"
run apply; assert_rc $? 0 "apply is a no-op"

echo "== no battery at all: module hidden =="
rm -rf "$root/i"; mkdir -p "$root/i/sys/class/power_supply"
export BATTERY_SYSFS_ROOT="$root/i/sys"
out="$(run status)"
assert_contains "$out" '"text":""' "empty text hides the module"

assert_summary

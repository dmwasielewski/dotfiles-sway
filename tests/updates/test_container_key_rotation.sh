#!/bin/bash
# A container upgrade that fails its OpenPGP check gets ONE signing-key refresh
# and ONE retry; anything else stays a plain failure (2026-11-08, warpdotdev).
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" ACTION_LOG="$tmp/actions"
mkdir -p "$XDG_CACHE_HOME" "$tmp/bin"
# toolbox stub: the upgrade fails until a refresh succeeded (TEST_MODE decides).
cat > "$tmp/bin/toolbox" <<'STUB'
#!/bin/bash
[[ "$1" == list ]] && exit 0
shift 3                                       # run --container <name>
if [[ "$1" == sudo ]]; then                   # sudo -n bash -s -- <rpm>...
    shift 5; cat >/dev/null; echo "refresh $*" >> "$ACTION_LOG"
    [[ "$TEST_MODE" == rotated || "$TEST_MODE" == still-broken ]]; exit
fi
echo upgrade >> "$ACTION_LOG"
if [[ "$TEST_MODE" == unrelated ]]; then echo 'Curl error (28): Timeout'; exit 1; fi
if [[ "$TEST_MODE" == rotated ]] && grep -q refresh "$ACTION_LOG"; then echo Complete!; exit 0; fi
echo 'Transaction failed: Signature verification failed.'
echo 'OpenPGP check for package "tool-2-1.x86_64" (/var/cache/libdnf5/vendor-1/packages/tool-2-1.x86_64.rpm) from repo "vendor" has failed: Import of the key didn'"'"'t help, wrong key?'
exit 1
STUB
chmod +x "$tmp/bin/toolbox"
export PATH="$tmp/bin:$PATH"
source <(sed '/^trap refresh_waybar EXIT/d; /^# ── Main loop/,$d' "$DIR/scripts/updates-menu.sh" | sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR='$DIR/scripts'|")
discover_distrobox() { :; }
discover_toolbox() { echo dev; }
ensure_container_nopasswd() { return 0; }
ensure_container_repos_resilient() { :; }
upd_record() { :; }

run_case() { : > "$ACTION_LOG"; export TEST_MODE="$1"; do_containers > "$tmp/out" 2>&1; }

run_case rotated; rc=$?
assert_rc "$rc" 0 'rotated signing subkey: refresh + one retry succeeds'
assert_eq "$(cat "$ACTION_LOG")" $'upgrade\nrefresh /var/cache/libdnf5/vendor-1/packages/tool-2-1.x86_64.rpm\nupgrade' 'the failed package path is handed to the refresh'
assert_contains "$(cat "$LOG")" 'OK toolbox dev (after signing-key refresh)' 'log says why the retry happened'

run_case refused; rc=$?
assert_rc "$rc" 1 'refused refresh (new primary key) stays a failure'
assert_eq "$(cat "$ACTION_LOG")" $'upgrade\nrefresh /var/cache/libdnf5/vendor-1/packages/tool-2-1.x86_64.rpm' 'no retry after a refused refresh'
assert_contains "$(cat "$LOG")" 'KEY-REFRESH FAILED toolbox dev' 'refusal is logged'

run_case unrelated; rc=$?
assert_rc "$rc" 1 'unrelated error stays a failure'
assert_eq "$(cat "$ACTION_LOG")" upgrade 'unrelated error never triggers a key refresh'

run_case still-broken; rc=$?
assert_rc "$rc" 1 'retry that still fails is a failure'
assert_eq "$(cat "$ACTION_LOG")" $'upgrade\nrefresh /var/cache/libdnf5/vendor-1/packages/tool-2-1.x86_64.rpm\nupgrade' 'exactly one retry, never a loop'
assert_summary

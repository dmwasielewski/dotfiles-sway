#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_CACHE_HOME" "$tmp/bin"
export ACTION_LOG="$tmp/actions" TEST_MODE=recovered
cat > "$tmp/bin/rpm-ostree" <<'STUB'
#!/bin/bash
case "$1" in
 status) echo '{"deployments":[{"booted":true,"staged":false}]}' ;;
 refresh-md) echo refresh >> "$ACTION_LOG"; [[ "$TEST_MODE" != refresh-fails ]] ;;
 upgrade)
 echo upgrade >> "$ACTION_LOG"
 if [[ "$TEST_MODE" == signature ]]; then echo 'error: invalid signature'; exit 1; fi
 if [[ "$TEST_MODE" != recovered ]] || ! grep -q refresh "$ACTION_LOG"; then
  echo 'error: Could not depsolve transaction; 2 problems detected:'
  echo '  - package example-layer requires rpm-build, but none of the providers can be installed'
  exit 1
 fi ;;
esac
STUB
chmod +x "$tmp/bin/rpm-ostree"
export PATH="$tmp/bin:$PATH"
source <(sed '/^trap refresh_waybar EXIT/d; /^# ── Main loop/,$d' "$DIR/scripts/updates-menu.sh" | sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR='$DIR/scripts'|")
os_cached_raw() { echo 'No upgrade available.'; }
out="$(do_os)"; rc=$?
assert_rc "$rc" 2 'metadata recovery can complete without incorrectly claiming a staged update'
assert_eq "$(cat "$ACTION_LOG")" $'upgrade\nrefresh\nupgrade' 'dependency failure refreshes metadata and retries exactly once'
: > "$ACTION_LOG"; TEST_MODE=persistent; export TEST_MODE
out="$(do_os)"; rc=$?
assert_rc "$rc" 1 'persistent dependency conflict remains failure'
assert_eq "$(cat "$ACTION_LOG")" $'upgrade\nrefresh\nupgrade' 'persistent conflict never loops or removes packages'
assert_contains "$out" 'Repository/package versions are still incompatible' 'persistent conflict has an actionable explanation'
assert_contains "$(os_fail_reason)" 'dependency conflict' 'badge failure distinguishes dependency conflicts'
: > "$ACTION_LOG"; TEST_MODE=refresh-fails; export TEST_MODE
out="$(do_os)"; rc=$?
assert_rc "$rc" 1 'failed metadata refresh remains failure'
assert_eq "$(cat "$ACTION_LOG")" $'upgrade\nrefresh' 'failed refresh prevents a pointless upgrade retry'
assert_contains "$(os_fail_reason)" 'metadata refresh or upgrade retry failed' 'silent refresh failure does not reuse the previous dependency error'
: > "$ACTION_LOG"; TEST_MODE=signature; export TEST_MODE
out="$(do_os)"; rc=$?
assert_rc "$rc" 1 'signature failure is never treated as dependency mismatch'
assert_eq "$(cat "$ACTION_LOG")" upgrade 'unrelated errors do not trigger metadata recovery'
assert_summary

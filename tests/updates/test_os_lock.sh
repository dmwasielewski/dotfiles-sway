#!/bin/bash
# The badge's background check must never sabotage a user's update.
#
# Regression (2026-09-02): rpm-ostree serialises everything through one daemon
# transaction. The user started an OS update from the menu and it died instantly
# with "error: Transaction in progress: upgrade --check" — our own Waybar
# indicator was refreshing at that moment. Two of our own components fighting
# each other, and the user got the blame message.
#
# The rule: an update the user asked for wins; the background check skips the
# round and falls back to its last-known-good cache, which it already reports
# honestly. What it must NOT do is report "up to date" for a check that never ran.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"
cache="$tmp/cache"; mkdir -p "$cache"

# rpm-ostree would happily answer "no upgrade available" — the danger is that we
# believe it while someone else holds the transaction.
cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
[[ "$1" == "upgrade" ]] && { echo "No upgrade available."; exit 0; }
[[ "$1" == "status" ]] && { echo '{"deployments":[{"booted":true,"staged":false}]}'; exit 0; }
exit 0
STUB
chmod +x "$stub/rpm-ostree"

# Seed a last-known-good cache saying an update IS pending, so a wrong answer
# ("up to date") is distinguishable from the correct fallback.
printf 'AvailableUpdate:\n        Version: 44.99 (2026-09-02T00:00:00Z)\n           Diff: 7 upgraded\n' \
    > "$cache/os-check.cache"
date +%s > "$cache/os-check.ts"

# Hold the lock the way a running `rpm-ostree upgrade` would.
( flock 9; sleep 30 ) 9>"$cache/os-check.lock" &
holder=$!
trap 'kill "$holder" 2>/dev/null; rm -rf "$tmp"' EXIT
sleep 0.3

out="$(PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash -c '
    source "$1/scripts/lib-updates.sh"; os_check_raw' _ "$DIR")"
[[ -z "$out" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the background check yields nothing while an update holds the lock"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: the check ran anyway and would have collided (got [$out])"; }

state="$(PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash -c '
    source "$1/scripts/lib-updates.sh"; os_parse_state "$(os_check_raw)"' _ "$DIR")"
assert_eq "$state" "unknown" "a skipped check reads as unknown, never as current"

fresh="$(PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash -c '
    source "$1/scripts/lib-updates.sh"; os_refresh_cache' _ "$DIR")"
assert_eq "$fresh" "stale" "it falls back to the last-known-good cache instead of inventing an answer"

kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null

# With the lock free the check must work normally again.
out2="$(PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash -c '
    source "$1/scripts/lib-updates.sh"; os_check_raw' _ "$DIR")"
assert_contains "$out2" "No upgrade available" "the check runs normally once the lock is free"

assert_summary

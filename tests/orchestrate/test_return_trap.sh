#!/bin/bash
# A `trap ... RETURN` set inside a function must not outlive it.
#
# Regression (2026-08-19, found by the disposable-VM run): setup-nordvpn.sh did
#     local tmpdir; tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' RETURN
# The trap survives that function's return and fires AGAIN when the enclosing
# function returns — run_step, which called it. By then `tmpdir` is out of scope,
# so under `set -u` the install died with "tmpdir: unbound variable" reported
# against lib-install.sh, a file with no tmpdir in it.
#
# It only bites on a FRESH install: when the NordVPN repo and key already exist
# the function returns before setting the trap, which is why every run on a
# configured machine looked clean.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# The shape of the real code: run_step calls a helper that sets a RETURN trap.
cat > "$tmp/case.sh" <<'CASE'
#!/bin/bash
set -uo pipefail
source LIBPATH
helper() {
    local tmpdir; tmpdir="$(mktemp -d)"
    printf '%s' "$tmpdir" > TMPMARK
    trap "rm -rf \"\${tmpdir:-}\"; trap - RETURN" RETURN
}
run_step_like() { "$@"; }
run_step_like helper
later() { :; }
later
echo SURVIVED
CASE
sed -i "s|LIBPATH|$DIR/scripts/lib-install.sh|; s|TMPMARK|$tmp/mark|" "$tmp/case.sh"

out="$(STATE_FILE="$tmp/state" bash "$tmp/case.sh" 2>&1)" && rc=0 || rc=$?
assert_eq "$rc" "0" "a leaked RETURN trap does not abort a later function return"
assert_contains "$out" "SURVIVED" "execution continues past the enclosing function"

marked="$(cat "$tmp/mark" 2>/dev/null)"
[[ -n "$marked" && ! -d "$marked" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the temp directory is still cleaned up"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: temp directory left behind: $marked"; }

# And the real script must not carry the unguarded form any more.
if grep -q "trap 'rm -rf \"\$tmpdir\"' RETURN" "$DIR/scripts/setup-nordvpn.sh"; then
    ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: setup-nordvpn.sh still sets an unguarded RETURN trap"
else
    ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: setup-nordvpn.sh no longer sets an unguarded RETURN trap"
fi

assert_summary

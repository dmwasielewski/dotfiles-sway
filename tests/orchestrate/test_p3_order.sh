#!/bin/bash
# P3 must record completion BEFORE it disables the service running it.
#
# Regression (2026-09-02, first run that ever reached P3): the order was
# remove-sudoers → disable → rm stage → record INSTALL_COMPLETE. Phase 2 had
# succeeded (verify.sh inside the guest: 163 passed, 0 failed) and P3 started at
# 15:23:24 — one second later systemd terminated the job:
#
#   dotfiles-phase2.service: start operation timed out. Terminating.
#
# Everything after the disable was lost: no INSTALL_COMPLETE, and the three
# containers phase 2 had just built were SIGTERMed out of the service cgroup
# ("Exited (143)"). A finished install that looked unfinished.
#
# The disable is the one step that can cut its own phase short, so nothing may
# depend on running after it.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
log="$tmp/calls"

# orchestrate.sh dispatches on source, so lift out just the function under test.
sed -n '/^phase_P3() {/,/^}/p' "$DIR/orchestrate.sh" > "$tmp/p3.sh"
[[ -s "$tmp/p3.sh" ]] || { echo "  FAIL: could not extract phase_P3 from orchestrate.sh"; exit 1; }

STAGE="$tmp/stage"; mkdir -p "$STAGE"
remove_provisioning_sudoers() { echo "sudoers" >> "$log"; }
orch_set() { echo "set:$1" >> "$log"; }
systemctl() { echo "systemctl:$*" >> "$log"; }
# shellcheck source=/dev/null
source "$tmp/p3.sh"
phase_P3 >/dev/null

calls="$(tr '\n' ' ' < "$log")"
complete_at="$(grep -n '^set:INSTALL_COMPLETE' "$log" | head -1 | cut -d: -f1)"
disable_at="$(grep -n '^systemctl:.*disable' "$log" | head -1 | cut -d: -f1)"

[[ -n "$complete_at" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: P3 records INSTALL_COMPLETE"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: P3 never records INSTALL_COMPLETE (calls: $calls)"; }
[[ -n "$disable_at" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: P3 disables the phase-2 service"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: P3 never disables the service (calls: $calls)"; }
if [[ -n "$complete_at" && -n "$disable_at" ]]; then
    [[ "$complete_at" -lt "$disable_at" ]] \
        && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: completion is recorded before the service removes itself"; } \
        || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: the disable comes first, so a cut-short P3 loses the result (calls: $calls)"; }
    last="$(tail -1 "$log")"
    [[ "$last" == systemctl:*disable* ]] \
        && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the disable is the last thing P3 does"; } \
        || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: something runs after the disable and can be lost (last: $last)"; }
fi

# The unit itself must not sit under a start timeout: phase 2 legitimately runs
# for a quarter of an hour and the user manager's default is 45s.
unit="$DIR/systemd/user/dotfiles-phase2.service"
grep -qE '^TimeoutStartSec=infinity' "$unit" \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the unit disables the start timeout"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: no TimeoutStartSec=infinity — a long phase 2 gets killed again"; }

assert_summary

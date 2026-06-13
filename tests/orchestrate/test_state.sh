#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export STATE_FILE="$tmp/state"          # lib-install honours $STATE_FILE
source "$DIR/scripts/lib-orchestrate.sh"

orch_set REPO_COMMIT abc123
assert_eq "$(orch_get REPO_COMMIT)" "abc123" "set/get REPO_COMMIT"

# phases are ordered P0<P1<P2<P3; mark_phase records the latest completed
mark_phase P1
assert_eq "$(orch_get PHASE)" "P1" "mark_phase records PHASE"
phase_is_done P0 && echo "  ok: P0 done after P1" || { echo "  FAIL"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
phase_is_done P1 && echo "  ok: P1 done" || { echo "  FAIL"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
phase_is_done P2 && { echo "  FAIL: P2 wrongly done"; ASSERT_FAIL=$((ASSERT_FAIL+1)); } || echo "  ok: P2 not done"
assert_summary

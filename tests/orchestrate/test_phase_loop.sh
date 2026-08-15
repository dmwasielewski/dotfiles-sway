#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export STATE_FILE="$tmp/state"
source "$DIR/scripts/lib-orchestrate.sh"

LOG="$tmp/log"
phase_P0() { echo P0 >> "$LOG"; }
phase_P1() { echo P1 >> "$LOG"; }
phase_P2() { echo P2 >> "$LOG"; }
phase_P3() { echo P3 >> "$LOG"; }

mark_phase P1                 # P0,P1 already done
orchestrate_run_remaining
assert_eq "$(tr '\n' ' ' < "$LOG")" "P2 P3 " "runs only remaining phases in order"
# each completed phase is recorded
assert_eq "$(orch_get PHASE)" "P3" "PHASE advanced to P3"

# a fresh run (no PHASE) runs everything
: > "$LOG"; orch_set PHASE ""
orchestrate_run_remaining
assert_eq "$(tr '\n' ' ' < "$LOG")" "P0 P1 P2 P3 " "fresh run executes all phases"
# A failing phase must stop the run, stay unmarked, and report non-zero.
# Without this the engine marked a failed phase done, ran the remaining phases
# and reported a successful install — and a resume would skip the phase forever.
: > "$LOG"; orch_set PHASE ""
phase_P1() { echo P1 >> "$LOG"; return 1; }
orchestrate_run_remaining && rc=0 || rc=$?
assert_eq "$(tr '\n' ' ' < "$LOG")" "P0 P1 " "stops at the failing phase"
assert_eq "$rc" "1" "returns non-zero when a phase fails"
assert_eq "$(orch_get PHASE)" "P0" "failed phase is NOT marked done, so a resume retries it"
assert_eq "$(orch_get PHASE_FAILED)" "P1" "records which phase failed"

assert_summary

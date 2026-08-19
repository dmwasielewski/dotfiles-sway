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

# PHASE_FAILED must describe THIS run from the moment it starts. It is written on
# failure and cleared only when a phase later SUCCEEDS, so while a resumed run is
# still working the marker from the previous run is still on disk. Anything
# reading it from outside — the VM harness polls exactly this file — concludes
# the current run has failed when it is merely still going. Clear it up front.
orch_set PHASE ""; orch_set PHASE_FAILED "P1"
seen=""
phase_P0() { seen="$(orch_get PHASE_FAILED)"; echo P0 >> "$LOG"; }
phase_P1() { echo P1 >> "$LOG"; }
: > "$LOG"
orchestrate_run_remaining >/dev/null
assert_eq "$seen" "" "the previous run's failure marker is gone before the first phase runs"

orch_set PHASE ""; orch_set PHASE_FAILED "P3"
phase_P0() { echo P0 >> "$LOG"; }
phase_P1() { echo P1 >> "$LOG"; return 1; }
: > "$LOG"
orchestrate_run_remaining >/dev/null 2>&1 || true
assert_eq "$(orch_get PHASE_FAILED)" "P1" "a new failure replaces the old marker rather than leaving it"

assert_summary

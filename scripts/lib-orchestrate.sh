#!/bin/bash
# Orchestrator engine: state keys, phase ordering, deployment id, sudoers content,
# and the resumable phase loop. Source this; do not execute. Pure/testable parts
# only — privileged actions live in orchestrate.sh phase bodies.

ORCH_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-install.sh
source "$ORCH_HERE/lib-install.sh"

# Ordered phases. The loop runs each not-yet-done phase in this order.
ORCH_PHASES=(P0 P1 P2 P3)

orch_set() { step_save "$1" "$2"; }          # reuse lib-install's state file
orch_get() { step_get "$1"; }

# index of a phase name in ORCH_PHASES, or -1
phase_index() {
    local i
    for i in "${!ORCH_PHASES[@]}"; do
        [[ "${ORCH_PHASES[$i]}" == "$1" ]] && { echo "$i"; return; }
    done
    echo "-1"
}

# mark_phase records the latest completed phase name
mark_phase() { orch_set PHASE "$1"; }

# a phase is done if the recorded PHASE index is >= this phase's index
phase_is_done() {
    local want done_idx
    want="$(phase_index "$1")"
    local rec; rec="$(orch_get PHASE)"
    [[ -n "$rec" ]] || return 1
    done_idx="$(phase_index "$rec")"
    [[ "$done_idx" -ge "$want" ]]
}

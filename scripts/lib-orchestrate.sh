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

# Run every phase not yet done, in order, marking each done as it finishes.
# Phase bodies are functions phase_P0..phase_P3 defined by the caller
# (orchestrate.sh for real runs; tests provide stubs). A phase that reboots
# (P1) marks itself done before rebooting, so this loop never returns past it.
orchestrate_run_remaining() {
    local p
    # Start clean: PHASE_FAILED is written on failure and cleared only when a
    # phase later SUCCEEDS, so a resumed run carries the previous run's marker
    # for as long as it is still working. Anything watching from outside — the
    # VM harness polls this very file — then reads a run in progress as a run
    # that failed. The marker must describe this run from its first moment.
    orch_set PHASE_FAILED ""
    for p in "${ORCH_PHASES[@]}"; do
        phase_is_done "$p" && continue
        echo "==> phase $p"
        # The phase's exit status is the whole point: orchestrate.sh runs under
        # `set -uo pipefail` with NO `-e`, so an unchecked call let a failed phase
        # be marked done, the remaining phases run anyway, and the engine report a
        # successful unattended install. Worse, `phase_is_done` would then skip
        # the failed phase on every later resume, so it could never be retried.
        if ! "phase_$p"; then
            orch_set PHASE_FAILED "$p"
            echo "orchestrate: phase $p FAILED — stopping. It is not marked done," >&2
            echo "orchestrate: so re-running resumes at $p once the cause is fixed." >&2
            return 1
        fi
        orch_set PHASE_FAILED ""     # clear a previous failure once the phase passes
        mark_phase "$p"
    done
}

# Parse the booted deployment checksum from `rpm-ostree status --json` (stdin).
deployment_id_from_json() {
    python3 -c '
import json,sys
d=json.load(sys.stdin)
for dep in d.get("deployments",[]):
    if dep.get("booted"):
        print(dep.get("checksum","")); break
'
}

# Live booted deployment id (empty if rpm-ostree is unavailable, e.g. in a container).
current_deployment_id() {
    rpm-ostree status --json 2>/dev/null | deployment_id_from_json
}

ORCH_SUDOERS=/etc/sudoers.d/10-dotfiles-provisioning

# Pure: emit the scoped sudoers content for $1=user. Limited to the provisioning
# commands the orchestrated scripts actually call unattended.
provisioning_sudoers_content() {
    local user="$1"
    cat <<EOF
# Temporary, written by the dotfiles orchestrator; removed in phase P3 (finalize).
$user ALL=(ALL) NOPASSWD: /usr/bin/rpm-ostree, /usr/bin/systemctl, /usr/bin/loginctl, /usr/sbin/usermod, /usr/bin/mkdir, /usr/bin/tee
EOF
}

# Privileged: install/remove the drop-in (validated with visudo -c before install).
write_provisioning_sudoers() {
    local tmp; tmp="$(mktemp)"
    provisioning_sudoers_content "$USER" > "$tmp"
    # Validate BEFORE anything reaches /etc/sudoers.d. A malformed drop-in there
    # can break sudo for the whole system, and once it has, sudo can no longer be
    # used to remove the file that broke it. The previous order — install, then
    # check — made the check decorative, and its result was not even tested.
    # `visudo -cf` needs no privileges to check a file we own.
    if ! visudo -cf "$tmp" >/dev/null 2>&1; then
        echo "orchestrate: generated sudoers content is invalid — refusing to install it:" >&2
        sed 's/^/  /' "$tmp" >&2
        rm -f "$tmp"; return 1
    fi
    if ! sudo install -m 0440 -o root -g root "$tmp" "$ORCH_SUDOERS"; then
        echo "orchestrate: failed to install $ORCH_SUDOERS" >&2
        rm -f "$tmp"; return 1
    fi
    rm -f "$tmp"
    # Re-check what actually landed on disk, and undo it if it does not parse.
    if ! sudo visudo -cf "$ORCH_SUDOERS" >/dev/null; then
        echo "orchestrate: installed $ORCH_SUDOERS does not validate — removing it" >&2
        sudo rm -f "$ORCH_SUDOERS"; return 1
    fi
}
remove_provisioning_sudoers() { sudo rm -f "$ORCH_SUDOERS"; }

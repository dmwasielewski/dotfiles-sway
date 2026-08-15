#!/bin/bash
# Install orchestrator entrypoint. `run` starts a fresh install (P0..P1, reboots);
# `resume` (the phase-2 service) continues after the reboot (P2..P3).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib-orchestrate.sh
source "$HERE/scripts/lib-orchestrate.sh"
setup_logging "orchestrate.sh"

STAGE="$HOME/.local/state/dotfiles-secrets"

phase_P0() {
    # Without the scoped sudoers drop-in every later phase would block on a
    # password prompt with no TTY, so a failure here must stop the run.
    write_provisioning_sudoers || return 1
    orch_set REPO_COMMIT "$(git -C "$HERE" rev-parse HEAD)"
    mkdir -p "$STAGE"; chmod 700 "$STAGE"
    # vault secrets were harvested by install-from-usb.sh into $STAGE already.
}

phase_P1() {
    # `|| return 1` on every step: this script runs under `set -uo pipefail` with
    # no `-e`, so an unchecked failure here used to reboot the machine anyway and
    # hand a broken phase 1 to phase 2. Rebooting on top of a failed setup.sh is
    # the worst possible response, because the evidence scrolls away with it.
    bash "$HERE/setup.sh"    || return 1
    bash "$HERE/packages.sh" || return 1
    bash "$HERE/scripts/setup-orchestrator-service.sh" || return 1
    orch_set PRE_REBOOT_DEPLOYMENT "$(current_deployment_id)"
    mark_phase P1            # record before rebooting so resume continues at P2
    echo "rebooting for the new rpm-ostree deployment..."
    sudo systemctl reboot
    exit 0
}

phase_P2() {
    # Confirm we actually booted the new deployment before continuing.
    local now pre; now="$(current_deployment_id)"; pre="$(orch_get PRE_REBOOT_DEPLOYMENT)"
    [[ -n "$now" && "$now" != "$pre" ]] || echo "warning: deployment unchanged ($now)"
    orch_set DEPLOYMENT_ID "$now"
    # check-hardware is advisory (it reports GPU/VA-API/KVM findings), so it stays
    # tolerant. The rest build the environment the install is for — a failure
    # there must stop the run rather than be papered over by the final verify.
    bash "$HERE/scripts/check-hardware.sh"            || true
    bash "$HERE/scripts/setup-kvm.sh"                 || return 1
    bash "$HERE/scripts/setup-damian-container.sh"    || return 1
    bash "$HERE/scripts/setup-ubuntu-dev-container.sh" || return 1
    bash "$HERE/scripts/setup-security-container.sh"  || return 1
    # Apply the harvested vault manifest. VAULT_MOUNT must point at the on-disk
    # staging (the real ~/.vault is locked/unmounted after P0).
    if [[ -f "$STAGE/install/manifest.toml" ]]; then
        VAULT_MOUNT="$STAGE" bash "$HERE/scripts/vault/vault-apply-manifest.sh" "$STAGE/install/manifest.toml" || return 1
    fi
    bash "$HERE/scripts/verify.sh" --profile post-reboot || return 1
}

phase_P3() {
    remove_provisioning_sudoers
    systemctl --user disable dotfiles-phase2.service 2>/dev/null || true
    rm -rf "$STAGE"
    orch_set INSTALL_COMPLETE "$(date -Is)"
    echo "install complete."
}

case "${1:-run}" in
    run)    orchestrate_run_remaining ;;
    resume) orchestrate_run_remaining ;;
    *) echo "usage: orchestrate.sh [run|resume]" >&2; exit 2 ;;
esac

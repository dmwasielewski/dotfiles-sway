# Orchestrator end-to-end validation (disposable VM)

These steps are **host-run**, not CI. They validate the full unattended flow
(P0 → P1 → rpm-ostree reboot → P2 → P3) on a throwaway VM, advancing BACKLOG #5
(VM validation through the reboot into phase 2). The unit suite
(`bash tests/orchestrate/run.sh`) already covers the engine logic.

## What the orchestrator does (recap)

`scripts/install-from-usb.sh` clones the repo, unlocks the vault USB, takes one
sudo credential, harvests secrets to `~/.local/state/dotfiles-secrets`, and runs
`orchestrate.sh run`:

- **P0** writes the scoped `/etc/sudoers.d/10-dotfiles-provisioning`, records `REPO_COMMIT`.
- **P1** runs `setup.sh` + `packages.sh`, enables `dotfiles-phase2.service` (linger), reboots.
- **P2** (the user service, after reboot) runs hardware/KVM/container setups, applies the
  vault manifest, and `verify.sh --profile post-reboot`.
- **P3** removes the sudoers drop-in, disables the service, wipes the staging, records `INSTALL_COMPLETE`.

## Procedure

1. **Provision the VM and run the orchestrator:**
   ```bash
   bash ~/dotfiles-sway/scripts/create-fedora-sway-vm.sh
   ```
   The disposable-VM kickstart grants `%wheel NOPASSWD` (verified in
   `kickstarts/fedora-sway-atomic.ks`), so P0's sudo is a no-op there.

   The script defaults to `VM_INSTALL_MODE=orchestrator`: it clones the repo,
   runs `orchestrate.sh run`, survives the phase-1 reboot, waits for the guest,
   and then reports whether phase 2 resumed on its own. **This is the whole
   point of the test** — `VM_INSTALL_MODE=bootstrap` runs the classic
   `bootstrap.sh` path instead, which never enables `dotfiles-phase2.service`
   and therefore cannot answer the linger question at all. Until 2026-08-14 the
   script only had the bootstrap path while this README told you to check
   phase 2, so the check could not pass for a reason that had nothing to do with
   linger.

   Expect a long pause during `packages.sh`: the ChatGPT desktop step downloads
   ~420 MB inside the guest. It is `run_step_warn`, so a CDN failure is recorded
   and the install continues.

2. **After the VM reboots, confirm phase 2 resumed automatically:**
   ```bash
   systemctl --user status dotfiles-phase2.service
   cat ~/.dotfiles-install-state            # expect PHASE=P3 and INSTALL_COMPLETE=<timestamp>
   ```
   If the service did not run after the reboot, the `linger` assumption failed — fall
   back to a Sway-session autostart trigger (`exec orchestrate.sh resume` in `sway/config`)
   and note it in `scripts/setup-orchestrator-service.sh`.

3. **Full verification exits clean:**
   ```bash
   bash ~/dotfiles-sway/scripts/verify.sh --profile full ; echo "rc=$?"
   ```
   Expect `rc=0` (required checks pass).

4. **Finalize cleaned up:**
   ```bash
   test ! -e /etc/sudoers.d/10-dotfiles-provisioning && echo "sudoers drop-in removed ✓"
   systemctl --user is-enabled dotfiles-phase2.service ; echo "(expect: disabled)"
   test ! -d ~/.local/state/dotfiles-secrets && echo "secret staging wiped ✓"
   ```

## Resume / failure behaviour to spot-check

- Interrupt P2 (e.g. stop the VM mid-container-setup), reboot, and confirm the
  service re-runs `orchestrate.sh resume` and continues from the failed phase
  (`PHASE` in the state file did not advance past the failed phase).
- A `required` failure in `verify.sh --profile post-reboot` must leave the
  phase-2 service enabled (so it retries); only P3 disables it.

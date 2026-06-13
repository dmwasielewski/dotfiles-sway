# Design: install orchestrator (minimal phase runner)

**Date:** 2026-06-13
**Status:** Approved (design); implementation plan pending
**Repo:** dotfiles-sway
**Depends on:** the encrypted secrets vault (`docs/superpowers/specs/2026-06-12-secrets-vault-design.md`, built in `scripts/vault/`).
**Closes / advances:** BACKLOG #1 (orchestrator + reboot handoff); partially #7 (state), #11 (verify profiles); #8 (manifest-driven) explicitly deferred.

## Goal

Make a fresh Fedora Sway Atomic install reach the complete working system
(apps, containers, KVM, config, AI CLIs logged in) **without manual steps**
beyond a one-time launch input, bridging the gap the current flow leaves after
the rpm-ostree reboot (today the user runs five post-reboot scripts by hand).

## Decisions

- **Resume mechanism (chosen: A):** a **systemd user service** resumes phase 2
  automatically after the reboot. Rejected: root-only system units (awkward for
  the user-level work — rootless containers, `~` dotfiles, Sway session) and a
  re-entrant script the user re-runs (reintroduces a manual step).
- **Scope (chosen: minimal):** a thin **phase runner** that orchestrates the
  existing, already-tested scripts (`setup.sh`, `packages.sh`, `setup-kvm.sh`,
  the container setups, `verify.sh`). Not a full manifest-driven rebuild (#8) —
  that stays a later option. Reuse over rewrite (YAGNI).
- **Unattended root:** one-time `sudo -v` at launch writes a **scoped** sudoers
  drop-in for the few provisioning commands; phase 2 uses `sudo -n`; finalize
  **removes** the drop-in. The user's only launch input is the LUKS passphrase
  plus the sudo password.

## Architecture: the phase machine

`orchestrate.sh` runs phases in order, records state after each, and resumes from
the first non-`done` phase (skips completed ones).

```
P0 launch (USB, as user)
   - vault unlock (LUKS passphrase) ; sudo -v (sudo password, once)
   - write /etc/sudoers.d/10-dotfiles-provisioning (scoped NOPASSWD)
   - clone/verify repo at a recorded commit (clean checkout for unattended runs)
   - harvest vault secrets to ~/.local/state/dotfiles-secrets/ (0700 dir, 0600 files)

P1 bootstrap (as user)
   - setup.sh        (dotfiles symlinks, Flatpaks, toolbox create, fonts, neovim)
   - packages.sh     (rpm-ostree layering, via sudo -n)
   - cgroup delegation + podman.socket
   - enable dotfiles-phase2.service ; request reboot

   ──────────── REBOOT (rpm-ostree deployment) ────────────

P2 post-reboot (dotfiles-phase2.service, as user, sudo -n)
   - check-hardware.sh
   - setup-kvm.sh                 (libvirtd, groups, dotfiles-nat)
   - setup-damian-container.sh, setup-ubuntu-dev-container.sh, setup-security-container.sh
   - apply the vault manifest from staging (plant API keys; gh / nordvpn token logins)
   - verify.sh --profile post-reboot

P3 finalize
   - required checks passed?
       yes -> remove the provisioning sudoers drop-in
              disable dotfiles-phase2.service
              wipe ~/.local/state/dotfiles-secrets/
              record completion (REPO_COMMIT + DEPLOYMENT_ID)
       no  -> leave phase-2 service enabled; report; resume on next login / `orchestrate.sh resume`
```

## Components

- `orchestrate.sh` — the phase runner: a `resume`/`run` entrypoint that reads the
  current `PHASE` from state and executes the remaining phases. Phase definitions
  are an ordered, in-script list (case/array) mapping each phase to the existing
  scripts — **not** a separate manifest file (minimal scope).
- `install.sh` (lives on the USB next to the vault) — the launcher: `vault unlock`,
  `sudo -v`, clone the repo to `~/dotfiles-sway`, then `orchestrate.sh` from P0.
- `systemd/dotfiles-phase2.service` — user unit (`WantedBy=default.target`, enabled
  with lingering so it runs after reboot without requiring an interactive login)
  that runs `orchestrate.sh resume` and self-disables once `finalize` succeeds.
- Edits to `verify.sh` — add `--profile {phase1|post-reboot|full}` (default `full`,
  preserving today's behaviour). Required-vs-optional classification already exists
  (BACKLOG #4); the profile selects which required set must pass.
- Edits to `lib-install.sh` state — add `REPO_COMMIT`, `PHASE`, `DEPLOYMENT_ID`.

## State model (lightly improved, not full #7)

`~/.dotfiles-install-state` gains three keys:
- `REPO_COMMIT` — the commit the run is executing (recorded at P0; unattended runs
  require a clean checkout at this commit).
- `PHASE` — the last completed phase (`P0`…`P3`); `resume` continues after it.
- `DEPLOYMENT_ID` — the rpm-ostree booted-deployment checksum. The reboot is
  considered done only when the booted deployment differs from the one recorded
  before the reboot (replaces the permanently-`pending` `REBOOT_DONE`).

## Sudo lifecycle

At P0 the user runs `sudo -v` once. `orchestrate.sh` writes
`/etc/sudoers.d/10-dotfiles-provisioning` granting NOPASSWD for exactly the
provisioning commands (`rpm-ostree`, `systemctl`, `usermod`, and the cgroup-delegation
`mkdir`/`tee`). Phase 2 (the user service, no TTY) relies on `sudo -n` against this
rule. P3 deletes the drop-in. On the disposable validation VM the kickstart already
grants `%wheel NOPASSWD`, so P0 there is a no-op for sudo.

## Verify profiles (#11)

`verify.sh --profile`:
- `phase1` — symlinks, Flatpaks, host packages staged, base config (pre-reboot).
- `post-reboot` — hardware, KVM, containers, AI CLIs reachable, vault-planted creds.
- `full` — everything including optional/personal items (default; today's behaviour).

`finalize` requires the **required** checks of `post-reboot` to pass. Optional/warn
items never block (consistent with BACKLOG #4).

## Failure handling

A phase stops at the first **required** failure, records `failed`, and logs (same
tee'd log style as the update menu). The phase-2 service stays enabled, so the run
resumes from the failed phase on next login or via `orchestrate.sh resume`.
Optional (`run_step_warn`) failures do not block. Phases skip work already marked
`done`, so re-running is safe.

## Entry paths

- **Hardware (primary):** install Fedora Sway Atomic normally (user with a password),
  plug in the vault USB, run `install.sh` from it → P0.
- **VM (validation):** the disposable-VM kickstart (BACKLOG #6) + `create-fedora-sway-vm.sh`
  start P0 over SSH; NOPASSWD comes from the kickstart. Same engine, different launch.
  This also extends VM validation through reboot into phase 2 (advances BACKLOG #5).

## Manual limits (out of scope for automation)

GUI account logins (Bitwarden master, Spotify, Thunderbird/OAuth) and Bluetooth
pairing remain manual. Everything else — including `claude` / `codex` / `gh` /
`nordvpn` via vault keys/tokens — is automated.

## Out of scope (this spec)

- Manifest-driven engine that also generates docs (#8) — deferred; phases stay in-script.
- Full versioned/input-hashed state (#7) — only the three keys above are added now.
- Rewriting the existing setup scripts — they are orchestrated as-is.

## To verify during implementation

- systemd **user lingering** (`loginctl enable-linger`) actually runs the phase-2
  service after a reboot without an interactive login, in the Fedora Sway Atomic
  session model; otherwise fall back to a Sway-session autostart trigger.
- The exact minimal command set for the scoped sudoers drop-in (enumerate every
  `sudo` call across the orchestrated scripts).
- `rpm-ostree` deployment-checksum source for `DEPLOYMENT_ID`
  (`rpm-ostree status --json` → booted checksum).

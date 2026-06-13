# Backlog — dotfiles-sway

**Single source of truth for everything still to do.** Items to implement, fix, or
automate, ordered by priority. Do not keep parallel TODO lists elsewhere — CLAUDE.md
and the old `proposedChanges.md` audit have been folded into this file.

Legend: 🔴 critical · 🟠 high · 🟡 medium · ✅ done

---

## Install-pipeline correctness (from the 2026-06 install-flow audit)

The audit's headline finding: the repo does **not** yet deliver the advertised
"one script, fresh OS → ready system". It is a phase-1 bootstrap plus manually
run post-reboot scripts, and several steps report success before the component
actually works. These are ordered by the audit's priority list.

### 🔴 1. Resumable orchestrator + reboot handoff — ✅ BUILT (2026-06-13); VM validation pending
A minimal **phase runner** now bridges P0 (launch) → P1 (bootstrap) → rpm-ostree
reboot → P2 (post-reboot, via a systemd **user** service) → P3 (finalize), unattended.
Built: `orchestrate.sh`, `scripts/lib-orchestrate.sh` (state keys REPO_COMMIT/PHASE/
DEPLOYMENT_ID, resumable phase loop, deployment-id parsing, scoped provisioning
sudoers removed at finalize), `systemd/user/dotfiles-phase2.service` +
`scripts/setup-orchestrator-service.sh` (linger), `scripts/install-from-usb.sh`
(clone → vault unlock → harvest → run), and `verify.sh --profile {phase1|post-reboot|full}`.
Engine logic is unit-tested (`tests/orchestrate/`, all green); the real end-to-end
is validated in the disposable VM — see `tests/orchestrate/integration/README.md`.
Spec `docs/superpowers/specs/2026-06-13-orchestrator-design.md`, plan
`docs/superpowers/plans/2026-06-13-orchestrator.md`. The **encrypted secrets vault**
it consumes is also built (`scripts/vault/`). **Remaining:** run the VM end-to-end
once (confirms the systemd-linger resume; Sway-autostart fallback documented if it
fails). Manifest-driven rebuild (#8) and full versioned state (#7) stay deferred.

### 🔴 2. `setup.sh` no longer hard-depends on a to-be-layered package — ✅ DONE (2026-06-11)
`setup.sh` exited if `unzip` was missing, but `packages.sh` (which layers `unzip`)
runs *after* it, so a base image without `unzip` could never reach the step that
installs it. **Fixed:** font extraction now uses `unzip` when present and falls
back to `python3 -m zipfile -e` (python3 is in the Fedora base), and the fatal
check is gone. `unzip` stays in `packages.sh` as a convenience, not a phase-1 gate.

### 🔴 3. `verify.sh` exits nonzero on failure — ✅ DONE (partial, 2026-06-11)
`verify.sh` printed failures but always exited 0, so automation/CI/handoff saw a
broken install as success. **Fixed:** it now `exit 1` when `FAIL > 0`, else `exit 0`.
**Still TODO:** declarative profiles (`phase1` / `post-reboot` / `full` / `vm`) and a
machine-readable output mode, so optional/personal components (e.g. the personal
`win11` VM, lab tooling) don't invalidate the core install result. See item 11.

### 🟠 4. Eliminate false "ready" state transitions — ✅ DONE (2026-06-11)
Aggregate `*_READY=done` was written while the component could be unusable. Fixed:
- **KVM** (`setup-kvm.sh`): `KVM_SETUP_DONE` is now computed from the component
  states (requires `KVM_DEVICE_OK` = `/dev/kvm` present, plus user-group and
  network); without `/dev/kvm` it is marked `failed` and the summary says so.
- **NordVPN** (`setup-nordvpn.sh`): `NORDVPN_READY` is now derived from the real
  end state (CLI on PATH + `nordvpnd` active + user in `nordvpn` group). On the
  first pre-reboot run (package only staged) it is `pending`, not `done`.
- **Claude plugins** (both container setups): dropped the per-plugin `|| true`
  that guaranteed success; the install loop tracks an exit code so a real
  network/auth/marketplace failure marks the aggregate `failed`.
- **Security container** required-vs-optional aligned: `verify.sh` now treats
  `enum4linux-ng` and SecLists as **optional warnings** (matching the setup's
  `run_step_warn`), so the container is no longer reported broken for components
  the setup itself installs best-effort.

**Still open (broader):** full staged/booted/configured/authenticated state
vocabulary and sharing one required-vs-optional manifest between setup and verify
— folds into items 7 and 11.

### 🟠 5. VM validation through reboot + correct network
`scripts/create-fedora-sway-vm.sh` validates only phase 1 and hardcodes libvirt
network `default`, while the repo manages `dotfiles-nat`. **Do:** parameterise the
network (default to the repo-managed one after checking it's active), add
reboot/reconnect, then run phase 2 + a verification profile before declaring success.

### 🟠 6. Harden the kickstart — ✅ DONE (partial, 2026-06-11)
**Fixed:** plaintext password `damian` removed — `rootpw --lock` + a no-password
account reachable only by the injected SSH key (the VM script already logs in by
key). Destructive partitioning constrained to the single virtio disk via
`ignoredisk --only-use=vda` + `clearpart --drives=vda`, so it can never erase
extra disks on multi-disk hardware. Header now marks the file as the
disposable, isolated validation VM (not a general installer).
**Still TODO:** passwordless `wheel` sudo is kept because bootstrap runs unattended
over SSH (no TTY); it is acceptable only on this isolated, key-only, disposable VM.
Scoping it to provisioning commands and dropping it afterwards needs the
orchestrator (item 1). Parser-validate the rendered kickstart once ksvalidator is
available (item 9).

### 🟠 7. Replace ad-hoc state with versioned, input-aware state
`lib-install.sh` stores only a key + label. **Do:** record phase version, repo
commit, input/manifest hash, timestamps, staged/booted deployment IDs, error
detail; re-evaluate real conditions before skipping a phase. Also: `bootstrap.sh`
silently continues on a dirty checkout (different code, same "success" state) —
require a clean checkout at a recorded commit for unattended installs.

### 🟠 8. Unify autostart + generated docs from one phase manifest
bootstrap/README/CLAUDE keep separate, drifting next-step lists. The manual
autostart path also differs from normal login (Foot/Thunderbird divergence; the
Vivaldi-PWA divergence is now gone). **Do:** one idempotent session-bootstrap as
the only startup source (detect existing windows, no duplicates), and generate
next-step text from the same manifest the orchestrator/verifier use.

### 🟡 9. Static CI — ✅ DONE (infra, 2026-06-14)
`.github/workflows/ci.yml` runs on every push/PR to main: **lint** (`bash -n` +
`shellcheck -S error` on all 74 shell files), the **vault + orchestrator unit
suites**, and **ksvalidator** on the rendered kickstart. This is the static-CI
infrastructure plus the existing tests; the `set -e` counter bug is already fixed
(see "Concrete bugs" below) and rpm-ostree parsing has a fixture test.
**Still TODO (deeper coverage):** state-machine tests for interrupted / resume /
dirty-checkout / changed-manifest, and assertions that every aggregate `READY`
implies its required component states. These are new test cases to add over time,
not CI plumbing.

### Concrete bugs found by the audit
- ✅ **`((VERIFY_FAIL++))` under `set -e`** kills the container setup scripts at the first missing tool (post-increment returns 1 when the prior value is 0). **Fixed** → `VERIFY_FAIL=$((VERIFY_FAIL + 1))` in both setup scripts.
- ✅ **`lib-updates.sh` classified unknown rpm-ostree output as "current".** **Fixed** → the catch-all now returns `unknown` (degrades gracefully via the last-known-good cache) instead of falsely claiming up-to-date.
- ✅ **AdGuard `iptables` remediation was a no-op** (`verify.sh` said "run packages.sh", which doesn't install it). On Fedora Sway Atomic 44 `iptables` (iptables-nft) is in the **base image**, so it must not be layered. **Fixed** → remediation now points at the real recovery (`sudo rpm-ostree install iptables-nft && systemctl reboot`) for the unlikely base without it.
- ✅ **README idempotency claim corrected** (2026-06-11) — the "all scripts are safe to rerun and skip completed steps" line now honestly says re-running re-executes most steps and overwrites state (no state-driven resume; some steps are destructive on rerun). True idempotent convergence is still items 1 & 7.
- ✅ **Swallowed failures now recorded** (2026-06-11) — `setup.sh` yazi, Zed, the Podman socket and cgroup delegation use `run_step_warn` / explicit `step_done`/`step_failed`, so they appear in the install-state summary instead of vanishing into a plain echo. **Still TODO:** have `verify.sh` check every warning-only capability it claims is installed.

### 🟡 11. Verification: separate required / optional / personal / test-only
`verify.sh` mixes a personal `win11` VM, lab tooling, credentials, GUI apps and
core install into one result, and checks presence more than behaviour. **Do:**
declarative profiles + capability groups; add non-destructive behavioural checks
(`sway --validate`, desktop-file validation, systemd unit syntax, container→host
`podman info`, deployment reconciliation). Pairs with item 3.

---

## Planned features (from CLAUDE.md "What is planned")

- 🟠 **Windows Server 2022 VM** — Active Directory lab (AD Sysadmin Lab project)
- 🟡 **Kali Linux VM**
- 🟡 **virtiofs fully working in Windows 11** (VirtioFsSvc setup)
- 🟡 **`gh auth login` automation**
- 🟠 **Full idempotency audit** of `setup.sh` / `packages.sh` / post-reboot scripts (overlaps items 4 & 7)

---

## Small open items

- **yazi**: ✅ Sway keybind bound — `Mod+Y` opens yazi in a new foot terminal (2026-06-11). Still optional: a shell hook to `cd` into yazi's last dir on exit.
- **NordVPN**: a stale `NORDVPN_REPO=failed` lingers in the install-state file from a day the repo was unreachable — clear with `bash ~/dotfiles-sway/scripts/setup-nordvpn.sh`.
- **Thunderbird**: after message filters are recreated and tested manually, add `msgFilterRules.dat` to repo automation as symlinked profile files with one-time backups.

---

## Done (reference)

- ✅ **Waybar update module** — icon indicator + foot menu for Flatpak / containers / Fedora OS. Shared detection in `scripts/lib-updates.sh` (all names discovered dynamically, no hardcoding); 1h JSON cache; last-known-good OS cache; severity colours; menu ordered by update frequency.
- ✅ **Vivaldi + all 3 PWAs removed** (2026-06-11) — Firefox is the only browser; Claude/ChatGPT/WhatsApp are Firefox tabs.
- ✅ **DeepSeek TUI fixed** (2026-06-11) — npm package `deepseek-tui` → `codewhale`; wrapper resolves the binary on PATH; `deepseek` kept as an alias.
- ✅ **yazi** terminal file manager — user-local from GitHub release (`setup-yazi.sh`), tracked by the update module.
- ✅ **Zed** GUI editor — user-local upstream binary (`setup-zed.sh`), self-updating.
- ✅ **Neovim** from the OS package manager (rpm-ostree/dnf/apt) + Chris Titus Tech config.
- ✅ NordVPN / AdGuard CLI install + Waybar toggles; rpm-ostree + Flatpak update flow.

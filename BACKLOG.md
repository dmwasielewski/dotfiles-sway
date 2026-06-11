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

### 🔴 1. Resumable orchestrator + reboot handoff
There is no kickstart→bootstrap or reboot→phase-2 continuation. `kickstarts/fedora-sway-atomic.ks`
only reboots; `bootstrap.sh` ends at "reboot required" and prints manual commands.
**Do:** a first-boot unit that clones the exact commit and runs phase 1, then a
phase-2 unit that resumes after the new deployment boots; disable each unit only
after its phase verifies. Keep secrets/logins as explicit manual gates.

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

### 🟠 4. Eliminate false "ready" state transitions
Aggregate `*_READY=done` can be written while the component is unusable:
- NordVPN marked ready from a *staged* package before the daemon/group exist (`setup-nordvpn.sh`).
- security container marked ready after optional steps (enum4linux-ng, SecLists) only warn, yet `verify.sh` treats them as required failures.
- Claude plugin install uses `|| true` then marks done; `verify.sh` treats missing plugins as failures.
- KVM marks `KVM_SETUP_DONE=done` even when `/dev/kvm` is absent.
**Do:** use staged/booted/configured/authenticated states; compute aggregate
readiness from component states; classify required vs optional once and share it
between setup and verify.

### 🟠 5. VM validation through reboot + correct network
`scripts/create-fedora-sway-vm.sh` validates only phase 1 and hardcodes libvirt
network `default`, while the repo manages `dotfiles-nat`. **Do:** parameterise the
network (default to the repo-managed one after checking it's active), add
reboot/reconnect, then run phase 2 + a verification profile before declaring success.

### 🟠 6. Harden the kickstart
- `clearpart --all` with automatic partitioning can erase every visible disk → template an explicit disk + `ignoredisk --only-use=`.
- Plaintext password `damian` + unrestricted passwordless `wheel` sudo + SSH open → lock password auth, rely on injected SSH key, scope sudo to provisioning and remove it after.

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

### 🟡 9. Static CI
ksvalidator on the rendered kickstart, ShellCheck, `set -e` behaviour tests
(counters/functions in `if`), state-machine tests (clean/interrupted/failed-download/
resume/dirty-checkout/changed-manifest), rpm-ostree parse fixtures, and assertions
that every aggregate `READY` implies its required component states and that verifier
failures exit nonzero.

### Concrete bugs found by the audit
- ✅ **`((VERIFY_FAIL++))` under `set -e`** kills the container setup scripts at the first missing tool (post-increment returns 1 when the prior value is 0). **Fixed** → `VERIFY_FAIL=$((VERIFY_FAIL + 1))` in both setup scripts.
- ✅ **`lib-updates.sh` classified unknown rpm-ostree output as "current".** **Fixed** → the catch-all now returns `unknown` (degrades gracefully via the last-known-good cache) instead of falsely claiming up-to-date.
- ✅ **AdGuard `iptables` remediation was a no-op** (`verify.sh` said "run packages.sh", which doesn't install it). On Fedora Sway Atomic 44 `iptables` (iptables-nft) is in the **base image**, so it must not be layered. **Fixed** → remediation now points at the real recovery (`sudo rpm-ostree install iptables-nft && systemctl reboot`) for the unlikely base without it.
- 🟡 README claims "all scripts are safe to rerun and skip completed steps" — false; `run_step` re-executes and overwrites state, `setup.sh` force-replaces `~/.bashrc`. Fix the claim or implement true idempotent convergence.
- 🟡 Several noncritical failures are swallowed without state (`setup.sh` yazi/Zed, Podman socket/cgroup; corrupt configs). Use `run_step_warn` consistently and have verify check every warning-only capability.

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

- **yazi**: optional Sway keybind (`Mod+…` → `foot -e yazi`) — not bound yet (pick a non-conflicting key first); optional shell hook to `cd` into yazi's last dir on exit.
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

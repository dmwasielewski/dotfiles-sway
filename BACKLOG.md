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

### 🟠 5. VM validation through reboot — ✅ THE LINGER QUESTION IS ANSWERED (2026-08-19)

The risk this item existed for — *does `systemd-linger` resume phase 2 after the
reboot with nobody logged in?* — is settled, on a real guest rather than from
documentation. **Yes, it does.** The documented Sway-autostart fallback is not
needed.

Evidence, taken deliberately to rule out the one alternative explanation (that an
ssh login started the user manager):

```
system boot                 07:23:43
user@1000.service started   07:23:50   ← 7 s after boot
dotfiles-phase2.service     07:23:50   ← same second
first ssh login            ~07:28      ← five minutes later
Linger=yes
orchestrate.sh resume        running (pid 1122)
```

`scripts/create-fedora-sway-vm.sh` now runs the orchestrator path by default
(`VM_INSTALL_MODE=orchestrator`), starts it detached so a host interruption
cannot kill it, resumes an existing VM instead of rebuilding, and reports which
phase failed rather than waiting out a timeout.

**The network half is now done too (2026-08-31)**, and it was not cosmetic. The
guest installs `libvirt-daemon-config-network`, which defines libvirt's own
`default` network — 192.168.122.0/24, gateway .1 — *inside* the guest. Attaching
the guest to the host's `default` network put it on that same subnet, so the
moment `setup-kvm.sh` enabled libvirtd the guest raised `virbr0` with a
conflicting route to its own subnet and lost networking completely: pings and ssh
dead while the console sat happily at a login prompt.

`VM_NETWORK` now defaults to `dotfiles-nat` (192.168.125.0/24, no collision), the
script starts the network if it is defined but inactive, refuses if it does not
exist, and warns explicitly when the chosen network is on 192.168.122.x. All
three paths verified against the live libvirt networks.

**Four bugs surfaced only because this ran**, every one invisible on a
configured machine — see `AI_ERRORS.md`: the interactive `sudo -v` in an
unattended path, the RETURN trap outliving its function, `rpm -q` missing
already-requested packages so no resume could work, and `chmod +x` dirtying the
repo so `git pull` silently stopped.

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

### 🟠 11. Verification: separate required / optional / personal / test-only
**Now blocking, with evidence (2026-08-19).** `verify.sh --profile post-reboot`
is the last step of orchestrator phase P2, so whatever it fails on, the
unattended install fails on. In the test VM it reported 12 failures on an
install that had actually worked:

- **`VM 'win11' NOT FOUND`** — Damian's personal VM. Nothing in the repo creates
  it; the remedy literally says "create manually". Fixed: it is a warning now,
  because a check whose fix is a manual step cannot gate an automated one.
- **`User NOT in libvirt group`, `libvirtd not running`, `NAT network missing`** —
  `setup-kvm.sh` does add the group, but its own remedy says "then log out and
  back in". An install cannot satisfy that before it finishes.
- **`NordVPN background service NOT RUNNING`** — documented as a manual login step.
- **Four tools "MISSING in damianu"** (`bat`, `fd`, `sgpt`, `claude`) while
  `nvim`, `btop`, `duf`, `ncdu`, `rg`, `fzf` in the same container passed, and the
  install state recorded every one of them as installed. Re-probing by hand found
  all four present. These are timing-dependent false negatives, not missing
  tools — worth understanding before trusting any container check.

**Do:** classify every check as required / optional / personal / manual-step, and
let the profile that gates the install assert only what the install itself is
responsible for. Until then P2 cannot pass on a clean machine.

### 🟡 11b. (original wording)
`verify.sh` mixes a personal `win11` VM, lab tooling, credentials, GUI apps and
core install into one result, and checks presence more than behaviour. **Do:**
declarative profiles + capability groups; add non-destructive behavioural checks
(`sway --validate`, desktop-file validation, systemd unit syntax, container→host
`podman info`, deployment reconciliation). Pairs with item 3.

### 🟠 12. Update module ignores every language package manager — ✅ DONE (2026-09-01)
The Waybar update module has four sources — Flatpak, containers, OS, user-local
apps — and **none of them updates a single npm/pip package**. `do_containers()`
runs `distrobox upgrade` / toolbox `dnf`, which is the *distro* package manager
inside the container; the AI CLIs are installed on top of it with
`npm install -g` (`setup-damian-container.sh:96`, `setup-ubuntu-dev-container.sh:128`).
So `claude`, `codex`, `codewhale` and `markdownlint-cli2` — the tools used every
day — are updated by nobody and drift silently until noticed by hand. The same
hole covers `shell-gpt` and `faster-whisper`, installed with `pip3 install --user`.

**Do:** add a fifth source to `lib-updates.sh` covering language package managers
inside containers, discovered dynamically (never a hardcoded package list):
`npm -g outdated --json` and `pip list --outdated --format=json` per container,
run through the same container discovery already used by `discover_toolbox` /
`discover_distrobox`. It needs its own section in the tooltip, its own menu
entry, and a `upd_record` timestamp so "last updated" works like the others.
Found 2026-08-14 when a manual `npm i -g @openai/codex` turned out to be the
only way codex ever gets a new version.

**Done 2026-09-01.** Fifth source `langpkg_update_rows` in `lib-updates.sh`, its
own tooltip section, menu entry 3, a `langpkg` timestamp, and
`tests/updates/test_langpkg.sh`. First real run found 10 outdated packages that
nothing had been updating, including `claude` 2.1.158 → 2.1.257 and `codex`
0.147.0 → 0.152.0.

Two traps the implementation had to handle, both found by running it rather than
reasoning about it — do not "simplify" either away:

- **`$HOME` is shared with every container**, so `~/.npm-global` and
  `~/.local/lib/pythonX.Y/site-packages` are the same directory seen from all of
  them. Rows are deduplicated by install root; without it the same four pip
  packages were reported three times.
- **`npm -g outdated` returns `{}` in toolbox `damianf` and six packages in
  distrobox `damianu` for the SAME prefix.** The toolbox reaches `$HOME` through
  `/home` → `/var/home`, so npm sees the global tree as linked and skips it
  (`npm -g ls` prints `.npm-global/lib -> ./` there and a plain path in the
  distrobox). The union across containers is what keeps the correct answer
  winning. Residual risk worth knowing: if the distrobox were removed, npm
  updates would go unreported rather than reported as unknown — the empty answer
  is indistinguishable from a true empty one without a heuristic on that `-> ./`
  marker.

---

## Planned features (from CLAUDE.md "What is planned")

- 🟠 **Windows Server 2022 VM** — Active Directory lab (AD Sysadmin Lab project)
- 🟡 **Kali Linux VM**
- 🟡 **virtiofs fully working in Windows 11** (VirtioFsSvc setup)
- 🟡 **`gh auth login` automation**
- 🟠 **Full idempotency audit** of `setup.sh` / `packages.sh` / post-reboot scripts (overlaps items 4 & 7)

### 🟡 13. Claude Desktop — wait for a native Fedora package
Anthropic shipped an official Claude Desktop for Linux on 2026-06-30 (beta:
Chat, Cowork, Code). It is **.deb only**, via `https://downloads.claude.ai/claude-desktop/apt/stable`,
officially Ubuntu 22.04+ / Debian 12+. There is no RPM and Fedora is not
supported; Anthropic says more distributions are planned, with no date.

Installing it into the Ubuntu distrobox `damianu` and exporting it with
`distrobox-export --app` was investigated and **rejected by Damian on
2026-08-14**: GUI applications he uses daily must live in the Fedora layer, not
in a container. The container stays a development environment, not an app
delivery mechanism. Do not re-propose this route — see the rule in `CLAUDE.md`.

**Do:** periodically re-check for an RPM or an official Fedora repo. When one
exists, add `scripts/setup-claude-desktop.sh` modelled on `setup-chatgpt.sh`
(name-tracked rpm-ostree layer, `skip_if_unavailable` on the repo), route it to
a free workspace, and cover it in `verify.sh`. Until then Claude stays as the
`claude` CLI in toolbox `damianf` plus a Firefox tab.

### 🟠 14. The update module still has two blind spots after the 2026-08-18 fix
`flatpak_count` and the OS branch now say "could not check" instead of inventing
a zero (see `AI_ERRORS.md`). Two related gaps remain:

- **User-local tools skip silently.** `userlocal_update_rows` does
  `[[ -z "$latest" ]] && continue` when the GitHub API cannot be reached — no
  count, no note in the tooltip. It has a last-known-good tag cache, so the
  window is narrow, but an unauthenticated API is rate-limited to 60 requests an
  hour and a rate-limited reply is indistinguishable from "no newer release".
  *Partly advanced 2026-09-01:* a manifest may now declare
  `version_probe=<script in this repo> [args]` instead of `repo=`, so a tool
  whose releases are not on GitHub (the ChatGPT desktop app) is no longer
  skipped outright. The "silent skip on a failed lookup" gap above is unchanged
  and applies to probes too — a failing probe reports nothing.
- **Resume from suspend defeats the cache.** `CACHE_MAX_AGE` is 3 h, so a resume
  after that spawns a refresh immediately — typically before NetworkManager has
  connected. The result is now amber rather than a false all-clear, but it is
  still a wasted check that then sits for three hours.
  `XDG_RUNTIME_DIR` survives suspend, so the first-run-of-session force-refresh
  does not fire either. Options: retry the refresh when a check returns unknown
  (backoff), or hook `sleep.target` to invalidate the cache on resume. Needs a
  decision before code.

---

### 🟡 15. Report the ChatGPT `%post` breakage to OpenAI
From 26.831.20005 the package's `%post` does `mkdir -p /var/lib/chatgpt` and
`touch /var/lib/chatgpt/repository.keys`. `/var` is read-only inside
rpm-ostree's scriptlet sandbox — ostree packaging is supposed to create state
via `systemd-tmpfiles` — and the scriptlet runs under `set -e`, so the whole
atomic transaction aborts and **no OS update can install** while the package is
layered. That is why the app moved to a user-local install on 2026-09-01
(`scripts/setup-chatgpt.sh`).

Filing this upstream is the only route back to a layered, OS-tracked install.
Until then `verify.sh` fails if a layered copy reappears. Evidence to include:
the two `journalctl -t 'rpm-ostree(chatgpt.post)'` lines and the diff between
26.825's `%post` (no `/var` writes) and 26.831's `install_key()`.

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

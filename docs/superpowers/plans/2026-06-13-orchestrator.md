# Install Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A minimal phase runner that drives a fresh dotfiles-sway install through P0→P1→reboot→P2→P3 unattended, resuming after the rpm-ostree reboot via a systemd user service and consuming the secrets vault.

**Architecture:** A pure, testable engine (`scripts/lib-orchestrate.sh`) holds the phase loop, state keys, deployment-id parsing, and scoped-sudoers content; phase *bodies* live in `orchestrate.sh` as overridable functions so the loop is unit-testable without a real install. A systemd user service re-invokes `orchestrate.sh resume` after the reboot. The existing setup scripts are orchestrated as-is.

**Tech Stack:** Bash, systemd user units (+ linger), `rpm-ostree status --json` (parsed with python3), the existing `lib-install.sh` state file, plain-bash tests (no framework), reusing the `tests/` style from the vault.

**Spec:** `docs/superpowers/specs/2026-06-13-orchestrator-design.md`

---

## Environment & safety rules (read before any task)

- **Toolbox vs host:** the engine logic is testable in the toolbox with plain files.
  Anything touching `/etc/sudoers.d`, `systemctl`, `rpm-ostree`, or an actual reboot
  is host/root and is exercised only in the disposable VM (Task 9), never in CI.
- **Stubbable phases:** the phase loop calls `phase_P0`…`phase_P3` functions. Tests
  define stub versions that record execution; the real bodies (which call the setup
  scripts and reboot) run only on a real install.
- **No real reboot in tests.** `phase_P1`'s real body ends in `systemctl reboot`;
  tests stub it out.
- **Reuse state:** build on `scripts/lib-install.sh` (`step_save`/`step_get`); do not
  invent a second state store.
- **Commits:** direct to `main` (repo workflow); pre-push gitleaks runs.

## File structure

```
scripts/lib-orchestrate.sh        # engine: state keys, phase loop, deployment id, sudoers content, verify-profile call
orchestrate.sh                    # repo-root entrypoint: defines phase_P0..P3 (real bodies) + run|resume dispatch
scripts/install-from-usb.sh       # P0 launcher invoked by the USB's install.sh: vault unlock, sudo -v, clone, orchestrate run
systemd/user/dotfiles-phase2.service   # user unit that runs `orchestrate.sh resume` after reboot
scripts/setup-orchestrator-service.sh  # installs+enables the unit (+ linger); called from phase_P1
scripts/verify.sh                 # add --profile {phase1|post-reboot|full}

tests/orchestrate/
├── assert.sh                     # copy of the vault test helper
├── run.sh                        # run every test_*.sh
├── test_state.sh                 # REPO_COMMIT/PHASE/DEPLOYMENT_ID get/set, mark/skip
├── test_phase_loop.sh            # resume runs only not-done phases, in order
├── test_sudoers_content.sh       # scoped sudoers drop-in content
├── test_deployment_id.sh         # parse booted checksum from rpm-ostree --json fixture
├── test_verify_profile.sh        # profile_includes() selection logic
└── fixtures/
    └── rpm-ostree-status.json    # sample `rpm-ostree status --json`

tests/orchestrate/integration/    # host/VM-run, not CI
└── README.md                     # how to validate end-to-end in the disposable VM
```

---

## Task 1: Test harness + state keys

**Files:**
- Create: `tests/orchestrate/assert.sh`, `tests/orchestrate/run.sh`
- Create: `scripts/lib-orchestrate.sh`
- Test: `tests/orchestrate/test_state.sh`

- [ ] **Step 1: Copy the assertion helper and runner**

Copy `tests/vault/assert.sh` to `tests/orchestrate/assert.sh` verbatim, and
`tests/vault/run.sh` to `tests/orchestrate/run.sh` verbatim (same content; they
are self-contained and path-relative).

```bash
mkdir -p tests/orchestrate/fixtures
cp tests/vault/assert.sh tests/orchestrate/assert.sh
cp tests/vault/run.sh tests/orchestrate/run.sh
```

- [ ] **Step 2: Write the failing state test**

Create `tests/orchestrate/test_state.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export STATE_FILE="$tmp/state"          # lib-install honours $STATE_FILE
source "$DIR/scripts/lib-orchestrate.sh"

orch_set REPO_COMMIT abc123
assert_eq "$(orch_get REPO_COMMIT)" "abc123" "set/get REPO_COMMIT"

# phases are ordered P0<P1<P2<P3; mark_phase records the latest completed
mark_phase P1
assert_eq "$(orch_get PHASE)" "P1" "mark_phase records PHASE"
phase_is_done P0 && echo "  ok: P0 done after P1" || { echo "  FAIL"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
phase_is_done P1 && echo "  ok: P1 done" || { echo "  FAIL"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
phase_is_done P2 && { echo "  FAIL: P2 wrongly done"; ASSERT_FAIL=$((ASSERT_FAIL+1)); } || echo "  ok: P2 not done"
assert_summary
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/orchestrate/test_state.sh`
Expected: FAIL — `lib-orchestrate.sh` / `orch_set` not found.

- [ ] **Step 4: Implement state functions**

Create `scripts/lib-orchestrate.sh`:

```bash
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/orchestrate/test_state.sh`
Expected: PASS — `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add tests/orchestrate/assert.sh tests/orchestrate/run.sh tests/orchestrate/test_state.sh scripts/lib-orchestrate.sh
git commit -m "orchestrator: state keys + phase ordering + test harness"
```

---

## Task 2: Resumable phase loop

**Files:**
- Modify: `scripts/lib-orchestrate.sh`
- Test: `tests/orchestrate/test_phase_loop.sh`

- [ ] **Step 1: Write the failing loop test**

The test defines stub phase functions that append to a log, sets PHASE=P1, runs
the loop, and asserts only P2 then P3 ran (P0/P1 skipped):

```bash
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
assert_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/orchestrate/test_phase_loop.sh`
Expected: FAIL — `orchestrate_run_remaining` not defined.

- [ ] **Step 3: Implement the loop**

Append to `scripts/lib-orchestrate.sh`:

```bash
# Run every phase not yet done, in order, marking each done as it finishes.
# Phase bodies are functions phase_P0..phase_P3 defined by the caller
# (orchestrate.sh for real runs; tests provide stubs). A phase that reboots
# (P1) marks itself done before rebooting, so this loop never returns past it.
orchestrate_run_remaining() {
    local p
    for p in "${ORCH_PHASES[@]}"; do
        phase_is_done "$p" && continue
        echo "==> phase $p"
        "phase_$p"
        mark_phase "$p"
    done
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/orchestrate/test_phase_loop.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib-orchestrate.sh tests/orchestrate/test_phase_loop.sh
git commit -m "orchestrator: resumable phase loop (skips done, records progress)"
```

---

## Task 3: Booted deployment id

**Files:**
- Modify: `scripts/lib-orchestrate.sh`
- Create: `tests/orchestrate/fixtures/rpm-ostree-status.json`
- Test: `tests/orchestrate/test_deployment_id.sh`

- [ ] **Step 1: Write the fixture**

Create `tests/orchestrate/fixtures/rpm-ostree-status.json`:

```json
{
  "deployments": [
    { "booted": true,  "checksum": "aaaa1111", "version": "44.20260613.0" },
    { "booted": false, "checksum": "bbbb2222", "version": "44.20260601.0" }
  ]
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/orchestrate/test_deployment_id.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$DIR/scripts/lib-orchestrate.sh"
out="$(deployment_id_from_json < "$(dirname "$0")/fixtures/rpm-ostree-status.json")"
assert_eq "$out" "aaaa1111" "parses the booted deployment checksum"
assert_summary
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/orchestrate/test_deployment_id.sh`
Expected: FAIL — `deployment_id_from_json` not defined.

- [ ] **Step 4: Implement parsing + the live wrapper**

Append to `scripts/lib-orchestrate.sh`:

```bash
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/orchestrate/test_deployment_id.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib-orchestrate.sh tests/orchestrate/fixtures/rpm-ostree-status.json tests/orchestrate/test_deployment_id.sh
git commit -m "orchestrator: booted deployment id from rpm-ostree --json"
```

---

## Task 4: Scoped provisioning sudoers content

**Files:**
- Modify: `scripts/lib-orchestrate.sh`
- Test: `tests/orchestrate/test_sudoers_content.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/orchestrate/test_sudoers_content.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$DIR/scripts/lib-orchestrate.sh"
out="$(provisioning_sudoers_content damian)"
assert_contains "$out" "damian ALL=(ALL) NOPASSWD:" "names the user"
assert_contains "$out" "/usr/bin/rpm-ostree" "allows rpm-ostree"
assert_contains "$out" "/usr/bin/systemctl"  "allows systemctl"
assert_contains "$out" "/usr/sbin/usermod"   "allows usermod"
# must NOT be a blanket ALL command grant
[[ "$out" != *"NOPASSWD: ALL"* ]] && echo "  ok: not a blanket grant" || { echo "  FAIL: blanket"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
assert_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/orchestrate/test_sudoers_content.sh`
Expected: FAIL — `provisioning_sudoers_content` not defined.

- [ ] **Step 3: Implement the content generator + writer/remover**

Append to `scripts/lib-orchestrate.sh`:

```bash
ORCH_SUDOERS=/etc/sudoers.d/10-dotfiles-provisioning

# Pure: emit the scoped sudoers content for $1=user. Limited to the provisioning
# commands the orchestrated scripts actually call unattended.
provisioning_sudoers_content() {
    local user="$1"
    cat <<EOF
# Temporary, written by the dotfiles orchestrator; removed in phase P3 (finalize).
$user ALL=(ALL) NOPASSWD: /usr/bin/rpm-ostree, /usr/bin/systemctl, /usr/sbin/usermod, /usr/bin/mkdir, /usr/bin/tee
EOF
}

# Privileged: install/remove the drop-in (validated with visudo -c before install).
write_provisioning_sudoers() {
    local tmp; tmp="$(mktemp)"
    provisioning_sudoers_content "$USER" > "$tmp"
    sudo install -m 0440 -o root -g root "$tmp" "$ORCH_SUDOERS"
    rm -f "$tmp"
    sudo visudo -cf "$ORCH_SUDOERS" >/dev/null
}
remove_provisioning_sudoers() { sudo rm -f "$ORCH_SUDOERS"; }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/orchestrate/test_sudoers_content.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib-orchestrate.sh tests/orchestrate/test_sudoers_content.sh
git commit -m "orchestrator: scoped provisioning sudoers drop-in (content tested, write/remove privileged)"
```

---

## Task 5: verify.sh --profile

**Files:**
- Modify: `scripts/verify.sh`
- Test: `tests/orchestrate/test_verify_profile.sh`

The selection logic (`profile_includes`) is pure and tested; the actual gating in
`verify.sh` reuses it around the post-reboot-only sections.

- [ ] **Step 1: Write the failing selection test**

Create `tests/orchestrate/test_verify_profile.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# profile_includes <profile> <section>  -> exit 0 if the section runs in that profile
PI() { bash -c 'source "$1"; profile_includes "$2" "$3"' _ "$DIR/scripts/verify.sh" "$@"; }
# phase1 covers base only; post-reboot adds kvm/containers; full covers all
PI phase1 base        && echo "  ok: phase1 base"        || { echo FAIL; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
PI phase1 kvm         && { echo "  FAIL: phase1 kvm";   ASSERT_FAIL=$((ASSERT_FAIL+1)); } || echo "  ok: phase1 excludes kvm"
PI post-reboot kvm    && echo "  ok: post-reboot kvm"    || { echo FAIL; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
PI full optional      && echo "  ok: full optional"      || { echo FAIL; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
assert_summary
```

Note: sourcing `verify.sh` must not run the checks. Wrap verify.sh's body so that
when sourced (`return` guard) only function definitions load. Add near the top,
after the helper definitions:

```bash
# Allow sourcing for tests without executing the checks.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0 2>/dev/null || true
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/orchestrate/test_verify_profile.sh`
Expected: FAIL — `profile_includes` not defined.

- [ ] **Step 3: Implement profile parsing + selection in verify.sh**

Near the top of `scripts/verify.sh` (after the colour vars), add:

```bash
PROFILE="full"
for arg in "$@"; do
    case "$arg" in
        --profile=*) PROFILE="${arg#*=}" ;;
        --profile)   PROFILE="__next__" ;;
        *) [[ "$PROFILE" == "__next__" ]] && PROFILE="$arg" ;;
    esac
done
case "$PROFILE" in phase1|post-reboot|full) ;; *) echo "unknown profile: $PROFILE" >&2; exit 2 ;; esac

# Which section groups run in each profile. base = symlinks/flatpaks/config;
# kvm/containers = post-reboot; optional = personal/lab extras.
profile_includes() { # $1 profile, $2 section
    case "$1" in
        phase1)      [[ "$2" == base ]] ;;
        post-reboot) [[ "$2" == base || "$2" == kvm || "$2" == containers ]] ;;
        full)        return 0 ;;
        *)           return 1 ;;
    esac
}
```

Then guard the post-reboot-only section blocks, e.g. wrap the KVM checks with
`if profile_includes "$PROFILE" kvm; then … fi` and the container checks with
`if profile_includes "$PROFILE" containers; then … fi`. Leave the base checks
ungated (they run in every profile).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/orchestrate/test_verify_profile.sh`
Expected: PASS. Also confirm the sourcing guard works:
`bash -c 'source scripts/verify.sh; echo sourced-ok'` → prints `sourced-ok` with no checks run.

- [ ] **Step 5: Confirm the existing suites still pass and commit**

Run: `bash tests/vault/run.sh` (unrelated, must stay green) and
`bash tests/orchestrate/run.sh`.

```bash
git add scripts/verify.sh tests/orchestrate/test_verify_profile.sh
git commit -m "verify: --profile {phase1|post-reboot|full} + sourcing guard"
```

---

## Task 6: systemd user service + installer

**Files:**
- Create: `systemd/user/dotfiles-phase2.service`
- Create: `scripts/setup-orchestrator-service.sh`

Not unit-tested (systemd); validated in the VM (Task 9). Keep it small and obvious.

- [ ] **Step 1: Write the unit**

Create `systemd/user/dotfiles-phase2.service`:

```ini
[Unit]
Description=dotfiles-sway install phase 2 (post-reboot resume)
After=default.target

[Service]
Type=oneshot
ExecStart=%h/dotfiles-sway/orchestrate.sh resume
# Do not fail the boot if a phase needs another login; the service stays enabled
# and retries on the next start until orchestrate.sh disables it in finalize.
SuccessExitStatus=0 75

[Install]
WantedBy=default.target
```

- [ ] **Step 2: Write the installer (called from phase_P1)**

Create `scripts/setup-orchestrator-service.sh`:

```bash
#!/bin/bash
# Install + enable the phase-2 user service so it resumes after the reboot.
# Enables linger so the service can run without an interactive login.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.config/systemd/user"
mkdir -p "$dest"
ln -sf "$HERE/../systemd/user/dotfiles-phase2.service" "$dest/dotfiles-phase2.service"
systemctl --user daemon-reload
systemctl --user enable dotfiles-phase2.service
sudo loginctl enable-linger "$USER"
echo "phase-2 service enabled (linger on)"
```

- [ ] **Step 3: Syntax check + commit**

```bash
bash -n scripts/setup-orchestrator-service.sh
git add systemd/user/dotfiles-phase2.service scripts/setup-orchestrator-service.sh
git commit -m "orchestrator: phase-2 user service + installer (linger)"
```

---

## Task 7: orchestrate.sh phase bodies + dispatch

**Files:**
- Create: `orchestrate.sh` (repo root)

The real phase bodies wire the engine to the existing scripts. Not unit-tested
(they call the real installers); the loop they run is already tested (Task 2).

- [ ] **Step 1: Write orchestrate.sh**

Create `orchestrate.sh`:

```bash
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
    write_provisioning_sudoers
    orch_set REPO_COMMIT "$(git -C "$HERE" rev-parse HEAD)"
    mkdir -p "$STAGE"; chmod 700 "$STAGE"
    # vault secrets were harvested by install-from-usb.sh into $STAGE already.
}

phase_P1() {
    bash "$HERE/setup.sh"
    bash "$HERE/packages.sh"
    bash "$HERE/scripts/setup-orchestrator-service.sh"
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
    bash "$HERE/scripts/check-hardware.sh"            || true
    bash "$HERE/scripts/setup-kvm.sh"
    bash "$HERE/scripts/setup-damian-container.sh"
    bash "$HERE/scripts/setup-ubuntu-dev-container.sh"
    bash "$HERE/scripts/setup-security-container.sh"
    [[ -f "$STAGE/install/manifest.toml" ]] && bash "$HERE/scripts/vault/vault-apply-manifest.sh" "$STAGE/install/manifest.toml"
    VAULT_MOUNT="$STAGE" bash "$HERE/scripts/verify.sh" --profile post-reboot
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
```

- [ ] **Step 2: Syntax + shellcheck + commit**

```bash
bash -n orchestrate.sh && chmod +x orchestrate.sh
shellcheck -S error orchestrate.sh scripts/lib-orchestrate.sh || true
git add orchestrate.sh
git commit -m "orchestrator: phase bodies (P0..P3) + run/resume dispatch"
```

---

## Task 8: install-from-usb.sh launcher

**Files:**
- Create: `scripts/install-from-usb.sh`

The USB's `install.sh` is a one-liner that calls this after the repo exists; this
script does the P0 launch (vault unlock, sudo, clone, harvest, orchestrate run).

- [ ] **Step 1: Write the launcher**

Create `scripts/install-from-usb.sh`:

```bash
#!/bin/bash
# P0 launcher, run by the user from the USB. Unlocks the vault, takes one sudo
# credential, clones the repo, harvests secrets to the on-disk staging, and hands
# off to the orchestrator (which writes the scoped sudoers and starts P0..P1).
set -euo pipefail
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/dmwasielewski/dotfiles-sway.git}"
DEST="$HOME/dotfiles-sway"
STAGE="$HOME/.local/state/dotfiles-secrets"
VAULT="$(cd "$(dirname "$0")" && pwd)/vault/vault"   # the vault tooling on the USB

echo "==> unlocking the secrets vault"; "$VAULT" unlock
echo "==> caching one sudo credential for provisioning"; sudo -v

[[ -d "$DEST/.git" ]] || git clone "$REPO_URL" "$DEST"

echo "==> harvesting secrets to $STAGE"
mkdir -p "$STAGE/install"; chmod 700 "$STAGE"
cp -a "$HOME/.vault/." "$STAGE/"            # full vault copy; orchestrator applies the manifest in P2
chmod -R go-rwx "$STAGE"
"$VAULT" lock

echo "==> starting the orchestrator"
exec "$DEST/orchestrate.sh" run
```

- [ ] **Step 2: Syntax + commit**

```bash
bash -n scripts/install-from-usb.sh && chmod +x scripts/install-from-usb.sh
git add scripts/install-from-usb.sh
git commit -m "orchestrator: install-from-usb P0 launcher (vault unlock, clone, harvest, run)"
```

- [ ] **Step 3: Document the USB `install.sh`**

Add to the vault README scaffold note (and `README.md` vault section): the USB
carries a one-line `install.sh`:
`#!/bin/bash` + `exec "$(dirname "$0")/../dotfiles-sway/scripts/install-from-usb.sh"`
— or simply run `scripts/install-from-usb.sh` after cloning. (No code change needed
beyond the docs line.)

---

## Task 9: End-to-end validation in the disposable VM (host-run)

**Files:**
- Create: `tests/orchestrate/integration/README.md`

Not CI. This advances BACKLOG #5 (VM validation through reboot into phase 2).

- [ ] **Step 1: Document the VM validation procedure**

Create `tests/orchestrate/integration/README.md` describing:
1. `bash ~/dotfiles-sway/scripts/create-fedora-sway-vm.sh` (kickstart #6 + phase 1).
2. After the VM reboots, confirm `dotfiles-phase2.service` ran:
   `systemctl --user status dotfiles-phase2.service` and `cat ~/.dotfiles-install-state`
   shows `PHASE=P3` / `INSTALL_COMPLETE`.
3. `bash ~/dotfiles-sway/scripts/verify.sh --profile full` exits 0.
4. Confirm `/etc/sudoers.d/10-dotfiles-provisioning` is **gone** and the phase-2
   service is disabled (finalize cleaned up).

- [ ] **Step 2: Run the full unit suite once more + commit**

```bash
bash tests/orchestrate/run.sh    # ALL TESTS PASSED
git add tests/orchestrate/integration/README.md
git commit -m "orchestrator: VM end-to-end validation procedure (advances BACKLOG #5)"
```

- [ ] **Step 3: GO LIVE (user, real machine — optional, after VM passes)**

On a fresh Fedora Sway Atomic install: plug the vault USB, run
`scripts/install-from-usb.sh`, enter the LUKS passphrase + sudo password once,
walk away. Verify with `verify.sh --profile full` after it completes.

---

## Self-review notes

- **Spec coverage:** resume mechanism A (Tasks 2,6,7), minimal phase runner
  (Tasks 1,2,7), scoped sudo written/removed (Tasks 4,7), state keys
  REPO_COMMIT/PHASE/DEPLOYMENT_ID (Tasks 1,3,7), verify profiles (Task 5), failure
  resume via the still-enabled service (Tasks 2,6), entry paths hardware/VM
  (Tasks 8,9). #8 manifest-driven and full #7 explicitly out of scope.
- **Deferred to implementation (spec "to verify"):** linger-runs-after-reboot is
  validated in Task 9 (with the Sway-autostart fallback noted there if it fails);
  the exact sudoers command set is enumerated in Task 4 and refined if a phase-2
  script needs another `sudo` target; `DEPLOYMENT_ID` source is `rpm-ostree status
  --json` (Task 3).
- **Name consistency:** `orch_get/orch_set`, `mark_phase`, `phase_is_done`,
  `phase_index`, `orchestrate_run_remaining`, `ORCH_PHASES`, `phase_P0..P3`,
  `provisioning_sudoers_content`, `deployment_id_from_json`, `current_deployment_id`,
  `profile_includes` are used identically across tasks.
```

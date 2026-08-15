# Automation audit — plan

**Goal:** review the install and automation scripts for logic and behaviour
defects, starting with the one class that has already produced four separate
failures.

**Status:** pass 1 complete, pass 2 started. Ten fixes so far, each with a recorded repro.
One of them (the touchpad check) was only visible *because* an exit code was
made honest first — a good argument for doing this class before pass 2.

---

## Why this audit has an obvious starting point

Four instances of a single defect class surfaced in one day, none of them looked
for:

| Where | What happened |
|---|---|
| `scripts/verify.sh` | `grep -vi esr` matched nothing → exit 1 → `pipefail` + `set -e` → silent abort at section **1a of 20**. Output still ended in green ticks. **Fixed 2026-08-14.** |
| `scripts/setup-thunderbird.sh` | Non-matching glob → `ls` exit 2 → same chain → script dies at the profile lookup, making the "launch Thunderbird once" branch **unreachable dead code** in exactly the fresh-install case it was written for. **Fixed 2026-08-14.** |
| `scripts/create-fedora-sway-vm.sh` | P1's own `sudo systemctl reboot` kills the ssh session; under `set -euo pipefail` that would abort the script at the moment of interest. **Fixed 2026-08-14** (accepted exit + re-wait). |
| `scripts/vault/vault` | No `set -e`, `cryptsetup`/`mount` exit codes unchecked → prints `vault: unlocked` after both failed. **Fixed 2026-08-14**, with a stubbed repro: old printed `unlocked` and exited 0 after three failed sudo calls, new exits 1. |
| `scripts/lib-orchestrate.sh` | **The engine itself.** `orchestrate_run_remaining` ignored each phase's exit status and marked it done regardless, so a failed P1 still ran P2 and P3 and finished with `PHASE=P3`, exit 0 — a reported-successful unattended install on top of a failed phase. `phase_is_done` then skipped that phase on every resume, so it could never be retried. **Fixed 2026-08-14**, test-first. |
| `orchestrate.sh` | Phase bodies ran their steps unchecked, so a failed `setup.sh` still rebooted the machine and handed a broken phase 1 to phase 2. **Fixed 2026-08-14**; `check-hardware.sh` stays deliberately tolerant. |
| `write_provisioning_sudoers` | Installed the drop-in into `/etc/sudoers.d` **first** and ran `visudo -cf` on it **afterwards**, without checking the result — the comment claimed the opposite order. A malformed drop-in can break sudo system-wide, after which sudo cannot be used to remove it. **Fixed 2026-08-14**, test-first. |
| `scripts/install-from-usb.sh` | Hardcoded `$HOME/.vault` instead of `$VAULT_MOUNT`, and a stale empty directory made `cp -a` succeed while staging nothing — the install then locked the vault and continued with no secrets, silently, because the manifest step skips when the file is absent. **Fixed 2026-08-14**. |

Plus two already in `BACKLOG.md`: the `((VERIFY_FAIL++))` abort and audit item 4
("eliminate false ready state transitions").

These are not six unrelated bugs. They are one systematic weakness: **exit-status
handling, where "optional thing is absent" and "expected non-zero" cannot be
distinguished from "failed" — in both directions.** Either a harmless absence
kills the script, or a real failure is reported as success. Both were observed.

That makes pass 1 mechanical and verifiable rather than a matter of taste.

---

## Pass 1 — exit-status correctness

### Scope

Every tracked shell script: `bootstrap.sh`, `setup.sh`, `packages.sh`,
`orchestrate.sh`, `scripts/*.sh`, `scripts/vault/*`, `tests/**`.

### The four queries

1. Command substitutions whose pipeline can legitimately produce a non-zero
   status, in scripts with **both** `-e` and `pipefail`.
2. Scripts with **no** `set -e` that print a success line — every `sudo` and
   state-changing command before that line needs its exit code checked.
3. `run_step` / `run_step_warn` targets that can legitimately exit non-zero.
4. Success messages (`✓`, `done`, `ready`, `unlocked`, `complete`) not guarded
   by the result of the thing they claim succeeded.

### Method — non-negotiable, because the scan lies

A grep hit is a **candidate**, never a finding. For each one:

1. Read the surrounding code and decide whether the non-zero case is reachable.
2. Build an isolated repro **in a real script file**, then fix, then prove both
   the failure path and the happy path.
3. Only then write the fix, with a comment saying why the guard is load-bearing.

Three traps already caught during the first scan — expect more:

- **A subshell test lies.** `( set -euo pipefail; X=$(false|head -1); echo ok )`
  printed `ok`; the identical code in a real `.sh` file exited 2. The
  Thunderbird finding was nearly dismissed on the strength of the subshell run.
- **`head -12` is not a header.** `setup-chatgpt.sh` was flagged as missing
  `set -e` because its `set` line sits at line 21, below a long comment.
- **`grep '*e*'` matches `pipefail`.** A filter meant to select `set -e` scripts
  silently included every `set -uo pipefail` one.

### First-scan inventory (2026-08-14)

Scripts with no `set -e` that print success — each needs its own judgement, they
are not automatically wrong:

```
orchestrate.sh                  set -uo pipefail
scripts/check-hardware.sh       (no set)
scripts/install-devops-tools.sh set -uo pipefail
scripts/lib-install.sh          (no set)
scripts/updates-menu.sh         set -uo pipefail
scripts/vault/vault             set -uo pipefail   ← known bug, start here
tests/orchestrate/test_state.sh (no set)
```

Verified **safe**, do not re-flag: `scripts/thunderbird-id.sh` carries the same
`grep -vi esr | head` shape as the verify.sh bug but runs under `set -uo
pipefail` **without** `-e`, so the failing substitution cannot abort it. Tested
live: returns `org.mozilla.thunderbird_esr`, exit 0.

Cleared with evidence, do not re-flag: `verify.sh:101` (inside `if [[ -f
"$LOG_FILE" ]]`, so `du` cannot fail) and `verify.sh:573` (inside a
`command -v nvim` guard — hardened anyway, since a broken nvim binary would
otherwise take the remaining 15 sections with it). `setup-yazi.sh` and
`setup-zed.sh` run through `run_step_warn` in `setup.sh`, so a failed GitHub API
call is recorded in the install state rather than lost; failing there is the
wanted behaviour.

`check-hardware.sh` exited 0 even when it had counted failures and written
`HARDWARE_CHECK=failed`. Making the exit code agree with the verdict immediately
surfaced a real false negative: the touchpad check used `libinput list-devices`,
which needs root to open `/dev/input/event*`, so as a normal user it found no
touchpad on a laptop that has one. Now reads the world-readable
`/proc/bus/input/devices` with libinput as fallback. Both fixed 2026-08-14.

Remaining candidates from query 1, none yet verified: `setup-yazi.sh:20,40`,
`setup-zed.sh:34,65,73`, `setup-neovim-config.sh:72`,
`vault/setup-vault-usb.sh:39`, `nordvpn-waybar.sh:26`, `verify.sh:101,573`,
`create-fedora-sway-vm.sh:131`. Most end in `awk`/`find`/`head`, which exit 0 on
no match — the likely outcome is that most are fine, and saying so with evidence
is a valid result.

### Done: `scripts/vault/vault`

Both `unlock` and `lock` now check every privileged step and re-read the final
state through `vault_is_unlocked` instead of assuming it. A failed mount closes
the mapper again rather than leaving a decrypted-but-unmounted vault that
`status` would call locked. Reproduced with stubbed `lsblk`/`sudo` on PATH — no
hardware and no real passphrase needed, which is how the rest of pass 1 should
be tested too.

---

## Pass 2 — logic and behaviour

Only after pass 1, and each item needs a repro before a fix.

### Already checked, no action needed (do not re-investigate)

- **`waybar/config` is JSONC, not JSON.** A strict `json.load` fails on the `//`
  comments; Waybar parses it fine and the running bar uses this exact file.
- **`configure-shellgpt.sh` rewrites the whole `.sgptrc`**, dropping seven keys
  ShellGPT itself had written (cache paths, role storage, functions path,
  `PRETTIFY_MARKDOWN`). ShellGPT does not re-add them — it only writes the file
  when absent — but every dropped key has an identical default in
  `sgpt.config.DEFAULT_CONFIG`, verified directly, so behaviour is unchanged. The
  script is idempotent against itself, byte for byte.
- **`post-reboot` and `full` verify profiles are identical today** (20 sections
  each). Only `containers` and `kvm` are gated; nothing is classified optional or
  personal yet. That is backlog item 11, not a defect.
- **All 88 repo-internal file references resolve**, and all 77 shell scripts
  parse. Static warnings are down to 11, all style or loop variables.
- **The no-hardcoding rule holds.** No `/dev/sdX`, no hardcoded flatpak IDs in
  logic, no hardcoded username — every "damian" hit is the filename
  `setup-damian-container.sh`, and `VM_USER` is an overridable default.
- **Submodules are covered on both install paths.** `install-from-usb.sh` never
  calls `git submodule update`, but `setup-neovim-config.sh` initialises the one
  submodule it needs, and `setup.sh` calls it.
- **The phase-2 unit is sound.** `After=default.target` together with
  `WantedBy=default.target` looks like an ordering cycle but is not: a stub unit
  with the same stanzas was enabled here and systemd pulled it into
  `default.target` with no cycle reported. `systemd-analyze verify` is clean and
  `orchestrate.sh` is mode 100755, so `ExecStart` will not fail with 203/EXEC.
  Whether linger starts the user manager at boot is the one thing left that
  genuinely needs the VM.
- **Waybar helpers all return valid JSON and exit 0** (`updates`, `nordvpn`,
  `adguard`), and all three `verify.sh` profiles run to completion, exit 0, and
  reject an unknown profile with exit 2.

### Minor, recorded not fixed

- `dotfiles-phase2.service` sets `SuccessExitStatus=0 75`, but nothing in the
  orchestrator ever returns 75. The intent (a phase that needs another login
  should not mark the service failed) was never implemented. Harmless dead
  config; decide the semantics before writing code for it.
- `configure-shellgpt.sh:52` assigns `GEMINI_FALLBACK_MODEL` and never uses it.
  The fallback itself works — the generated wrapper reads
  `SHELLGPT_GEMINI_FALLBACK_MODEL` from the environment with the same default.

### Open:

- **Idempotency.** `README.md` already concedes that re-running re-executes most
  steps and overwrites state, and that some steps are destructive on rerun.
  Establish per-script what a second run actually does. Overlaps backlog 1 & 7.
- **Ordering assumptions.** `packages.sh` calls NordVPN, AdGuard and ChatGPT
  setups; `setup.sh` calls yazi and Zed. Which of these silently depend on a
  step that ran earlier, and what happens when one is run alone?
- **Blocking vs non-blocking.** Which failures should abort an unattended
  install and which should be recorded and skipped? Today this is decided
  per-script, without a stated rule. ChatGPT is `run_step_warn`, NordVPN and
  AdGuard are bare `bash` — that difference is deliberate but undocumented as a
  principle.
- **`verify.sh` coverage vs claims.** Backlog 11. Now more tractable: the script
  reaches its own summary for the first time.
- **Duplication between `sway/config` exec lines and `autostart.sh`.** The
  config launches four apps, `autostart.sh` relaunches three — they drifted
  once and will again. Overlaps backlog 8.

---

## Verification for the whole audit

- `bash scripts/verify.sh` reaches its summary and exits 0.
- `shellcheck --severity=warning` clean on every changed script.
- `bash tests/orchestrate/run.sh` and `bash tests/vault/run.sh` green.
- Every fix has a recorded repro proving the old behaviour, not only the new.
- Anything found that is not fixed goes to `BACKLOG.md` with its evidence.

## Explicitly out of scope

Rewriting the install engine. That is backlog items 7 and 8 and needs its own
design; this audit fixes defects in what exists and records what it cannot fix.

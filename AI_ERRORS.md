# AI_ERRORS.md — Lessons Learned for AI Assistants

> **Read this before making any changes to this repository.**
>
> This file records things that **DO NOT WORK** and why, plus what **DOES WORK**
> instead. Every AI session starts here to avoid repeating known mistakes.
>
> Only **real logic/architecture issues** are recorded, NOT transient failures
> (internet disconnects, timeouts, rate limits, etc.).

---

## 1. Tool Limitations (DeepSeek TUI environment)

### `exec_shell` — NOT AVAILABLE
**Problem:** The system prompt mentions `exec_shell`, but it's not in the actual tool catalog.
**Impact:** Any attempt to use `exec_shell` returns "Tool 'exec_shell' is not available".
**Fix:** Use `task_shell_start` + `task_shell_wait` instead.
```bash
# WRONG:
exec_shell "some command"
# RIGHT:
task_shell_start "some command"   # returns task_id
task_shell_wait <task_id> --wait  # polls and returns output
```

### `agent_spawn` / `spawn_agent` — NOT AVAILABLE
**Problem:** The system prompt describes sub-agent tools (`agent_spawn`, `agent_result`, `agent_wait`)
but they are absent from the actual tool schema.
**Impact:** Cannot delegate research to parallel sub-agents.
**Fix:** Do research inline (own knowledge). Use `task_create` for long-running background work.

### `web_search` — NOT AVAILABLE
**Problem:** No web search tool in the catalog.
**Fix:** Use own training knowledge for research. For URLs, use `fetch_url` if available.

---

## 2. Shell / Script Editing Pitfalls

### `sed` multi-line inserts with quoting
**Problem:** `sed -i '/marker/a line1\nline2'` with complex nested quotes (bash variables,
single quotes inside double quotes) causes unterminated string errors or literal `n` characters.
**Example failure:**
```bash
sed -i '/^Language packs/a \n### 24-hour time' CLAUDE.md
# Result: "n### 24-hour time" (literal 'n' before ###)
```
**Fix:** Use `code_execution` with Python for any non-trivial file edit:
```python
# Python handles quoting cleanly
lines = open(path).readlines()
lines.insert(idx, new_line)
open(path, 'w').writelines(lines)
```
**Alternative:** For single-line inserts, `sed` works fine. Only use Python for multi-line or
complex quoting.

### `task_shell_start` multi-line commands blocked
**Problem:** Commands with multiple lines (`&&`, `;`, newlines) are blocked for safety.
**Fix:** Run one command per `task_shell_start` call, or use `bash -c '...'` for simple
sequential commands.

---

## 3. Fedora Atomic Sway Rules (from CLAUDE.md)

### NEVER: `sudo dnf install`
**Problem:** Fedora Atomic is immutable. `dnf` does not exist on the host.
**Fix:** Use `rpm-ostree install` for host packages (requires reboot). Use Flatpak for GUI apps.
Use Toolbox/Distrobox for CLI tools.

### Flatpak must use `--user` in setup.sh
**Problem:** System Flatpaks (`sudo flatpak install`) trigger polkit prompts, blocking unattended setup.
**Fix:** Always `flatpak install -y --user flathub <app>` in `setup.sh`.
```bash
# WRONG:
flatpak install flathub org.mozilla.Thunderbird
# RIGHT:
flatpak install -y --user flathub org.mozilla.Thunderbird
```

### `flatpak override` needs `|| true` in setup.sh
**Problem:** `setup.sh` has `set -e`. If `flatpak override` fails (e.g., app not installed yet),
the entire setup aborts.
**Fix:** Always append `|| true`:
```bash
flatpak override --user --env=LC_TIME=en_GB.UTF-8 org.mozilla.Thunderbird || true
```

---

## 4. Config File Architecture

### Config dirs BEFORE symlinks
**Problem:** If `mkdir` for a config directory is missing, `ln -sf` creates a broken link
to a non-existent parent.
**Fix:** All `mkdir -p` calls must precede the corresponding `ln -sf` calls in `setup.sh`.

### Check for old FILES before creating symlinks
**Problem:** If a previous manual install created a regular file at the target path,
`ln -sf` will fail or create a symlink inside the existing directory.
**Fix:** The `ln -sf` flag handles this for files (overwrites), but for directories,
explicitly `rm -rf` first if the target might be a real directory. The safer approach is
to never manually create files that `setup.sh` symlinks.

### Print state summary after setup
**Problem:** After any install script finishes, the user needs to know what succeeded/failed.
**Fix:** Every script sources `lib-install.sh` and calls `print_state_summary` at the end,
or is called by `bootstrap.sh` which prints the summary.

---

## 5. Specific Workarounds

### DeepSeek TUI flicker on Sway/Foot
**Problem:** DeepSeek TUI repaints cause flicker with animations and mouse capture in Foot.
**Fix:** Wrapper script at `scripts/deepseek-wrapper.sh` sets `NO_ANIMATIONS=1` and
`--no-mouse-capture`. Do NOT remove these flags.

### Ubuntu 26.04 distrobox: apt HTTP pipelining 400 errors
**Problem:** Fresh Distrobox setup from `ubuntu:26.04` gets HTTP 400 from apt archives
with pipelining enabled.
**Fix:** `scripts/setup-security-container.sh` disables pipelining via
`Acquire::http::Pipeline-Depth "0";` during image build.

### ShellGPT: never block on missing API key
**Problem:** `sgpt` prompts interactively for an API key, blocking unattended setup.
**Fix:** `scripts/configure-shellgpt.sh` always writes a config file with
`OPENAI_API_KEY=missing-shellgpt-api-key` as placeholder. Do NOT remove this fallback.

### ShellGPT: don't overwrite custom sgpt
**Problem:** Damian might have a custom `~/.local/bin/sgpt`.
**Fix:** The configure script renames the repo-managed launcher to `sgpt-cli` and wraps it.
If an unmanaged `sgpt` exists, the script warns and leaves it untouched.

---

## 6. File Creation vs Symlinks in setup.sh

### `echo >` creates a FILE, not a SYMLINK
**Problem:** Manually running `echo 'content' > ~/.config/foo` when `setup.sh` expects a
symlink creates a conflict. On next `setup.sh` run, `ln -sf` may fail or behave unexpectedly.
**Fix:** When bootstrapping manually before `setup.sh` exists, always clean up with
`rm -f ~/.config/foo` before re-running `setup.sh` to let it create proper symlinks.
**Real case:** `~/.config/environment.d/locale.conf` was created as a file during manual
Thunderbird locale fix, then `setup.sh` was updated to symlink it. Had to `rm` the file first.

---

## 7. Git / GitHub Rules

### Never commit API keys
**Problem:** API keys in git history are permanent and a security risk.
**Fix:** All secrets go in `~/.bashrc.d/ai-keys.bash`, `~/.config/voice-type/gemini-api-key`,
or environment variables. These files are in `.gitignore` (or outside the repo entirely).

### Gitleaks pre-push hook
**Problem:** Pushing secrets is blocked by `.githooks/pre-push` running gitleaks.
**Fix:** This is intentional. If gitleaks blocks a push, the commit contains a secret — fix it.
Do NOT bypass the hook.

---

## 8. State & Logging

### All scripts must write state
**Problem:** Without state tracking, a failed install leaves no record of what broke.
**Fix:** Use `step_save`, `step_done`, `step_failed` from `lib-install.sh`. Output is logged
to `~/.dotfiles-install.log` with timestamps via `setup_logging`.

### verify.sh must check everything
**Problem:** If `verify.sh` doesn't check a component, it can't report whether it was installed.
**Fix:** Every new config file, symlink, Flatpak, or system package should have a corresponding
check in `verify.sh`. Categorize: `fail` (critical) vs `warn` (cosmetic).

---

## 9. Thunderbird-Specific

### Thunderbird Flatpak doesn't inherit system locale
**Problem:** `LC_TIME` set in `environment.d` doesn't reach Flatpak apps.
**Fix:** `flatpak override --user --env=LC_TIME=en_GB.UTF-8 org.mozilla.Thunderbird`.
Do NOT rely only on system locale for Flatpak Thunderbird.

### `user.js` for automated prefs, NOT ongoing config
**Problem:** `user.js` overrides manual settings on every Thunderbird start — confusing if
you don't know this.
**Fix:** Document in CLAUDE.md that `user.js` is copied ONCE during setup and enforces
prefs on every start. For one-time settings, use `about:config` directly.

---

## 10. Approval Prompt Behavior

### Approval only triggers for `task_shell_start`
**Problem:** The TUI shows an approval prompt for `task_shell_start` (shell commands) but
NOT for `code_execution` (Python) or `task_shell_wait`. This can cause silent waits.
**Fix:** When the user needs to approve, use `request_user_input` to explicitly ask.
When doing file writes via `code_execution`, note that no approval prompt will appear
— confirm with the user verbally in chat first.


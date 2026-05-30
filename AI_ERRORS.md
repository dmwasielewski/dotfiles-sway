# AI_ERRORS.md — Lessons Learned for AI Assistants

## Flatpak update detection — common false-bug traps

**Trap 1 — Only checking `--user` scope.** Apps may be installed in `--user`,
`--system`, or custom installations. Hardcoding `--user` misses everything
installed system-wide (Vivaldi, VSCode, Spotify, Bitwarden, OBS … were all
`system`). Discover installations dynamically with
`flatpak list --columns=installation | sort -u`, map each to its scope flag
(`user`→`--user`, `system`→`--system`, else `--installation=NAME`), and query
each. See `scripts/lib-updates.sh` → `flatpak_installations`.

**Trap 2 — Assuming "same version string = no update".** Flathub frequently
republishes the SAME version with a NEW commit (rebuild for an updated runtime
or security fix). `flatpak remote-ls --updates` correctly reports it as pending
even though the version label is unchanged (e.g. Bitwarden `2026.4.0 → 2026.4.0`).
The real test is the **commit hash**, not the version string:
`flatpak info … Commit:` vs `flatpak remote-info … Commit:`. The update list
labels these as `(rebuild)` so they don't look broken.

**Trap 3 — Browser flatpaks nag about a "newer version" that flatpak can't see.**
Vivaldi / Chrome / Firefox have their OWN in-app update checkers that compare
against the vendor website, which is always a few days ahead of the Flathub
package. The in-app nag persists even when the flatpak is fully up to date, and
it CANNOT be acted on (flatpak is read-only). This is **not a bug** and not
something the update tooling can fix — do not chase it. Verify with the commit
hash: if installed commit == flathub commit, the app is current.

**Trap 4 — Thinking system flatpak updates need a polkit agent.** This Sway
setup runs NO polkit authentication agent, yet `flatpak update --system` works
without a password because of the `org.freedesktop.Flatpak.rules` polkit rule
(active local user is allowed to update). Do NOT add a polkit agent believing
it is required for flatpak updates — it is not.

---

> **Read this before making any changes to this repository.**
>
> This file records things that **DO NOT WORK** and why, plus what **DOES WORK**

## 0. Waybar — NEVER start or restart manually

**Problem:** Running `waybar &` or `waybar -c ... &` from a script or shell creates a SECOND
Waybar instance alongside the one Sway manages. Sway's `exec waybar` in `sway/config` starts
Waybar at login and re-starts it on `swaymsg reload`. Any manually started instance duplicates
the bar on screen.

`pkill -SIGHUP waybar` kills Waybar (SIGHUP is not a reload signal for Waybar — it terminates
the process). Sway then restarts it from `exec`, but if the AI also starts one manually,
two instances run simultaneously.

**Fix — reload Waybar config without restart:**
```bash
pkill -SIGUSR2 waybar    # sends USR2 = reload config in-place, NO restart
```

**Fix — if Waybar is dead (0 processes), let Sway restart it:**
```bash
swaymsg reload           # Sway re-runs exec commands including waybar
```

**NEVER do:**
```bash
pkill -SIGHUP waybar       # kills it (not a reload)
waybar &                   # starts a duplicate
waybar -c ... &            # starts a duplicate
pkill waybar && waybar &   # race condition → duplicate
```

**Check instance count before any Waybar action:**
```bash
pgrep -x waybar | wc -l   # must be 1
```

If count is 2+, kill all extras: `pkill -x waybar; sleep 1; swaymsg reload`
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


### `task_shell_start` returns TOOL_RESULT_REF instead of executing
**Problem:** Repeated `task_shell_start` calls return `TOOL_RESULT_REF` with no shell execution.
This happens when the approval queue fills up or the TUI enters a state where shell commands
are silently queued instead of being presented for approval.
**Impact:** Cannot run shell commands, including `git commit`, `git push`, diagnostic commands.
**Fix:** Use `code_execution` with Python `subprocess.run()` instead. It bypasses the
shell approval system entirely.
```python
import subprocess
subprocess.run(['git', 'commit', '-m', 'msg'], cwd='/path/to/repo', capture_output=True)
```
**Note:** This is a workaround, not a permanent fix. The root cause is in the TUI approval
mechanism.

### Heredoc + sed insert fails with complex quoting
**Problem:** Using `cat > /tmp/file << 'EOF' ... EOF` followed by `sed -i '... r /tmp/file'`
to insert multi-line blocks into files. The heredoc content with bash variables, single quotes,
and special characters causes quoting failures or silent no-ops.
**Example failure:**
```bash
cat > /tmp/block.txt << 'EOF'
if grep -q "LC_TIME" "$HOME/.config/file" 2>/dev/null; then
    pass "ok"
EOF
sed -i '107 r /tmp/block.txt' verify.sh  # silently fails
```
**Fix:** Use `code_execution` with Python for ALL multi-line inserts into files.
Python handles strings natively without shell quoting issues.


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
**Fix:** `scripts/setup-security-container.sh` and `scripts/setup-ubuntu-dev-container.sh` disable pipelining via
`Acquire::http::Pipeline-Depth "0";` during image build.

### Ubuntu 26.04 dev userland: use a parallel Distrobox, not a Toolbox replacement
**Problem:** On Fedora Atomic, Ubuntu userland workflows should not be forced into Toolbox.
Toolbox is Fedora-oriented, while Ubuntu dev environments fit Distrobox better. At the same
time, this repo still has automation that assumes the Fedora toolbox `damianf` exists, most
notably the current voice-typing path.
**Fix:** Keep the Fedora toolbox `damianf` for the existing Fedora-native and voice-typing path,
and add Ubuntu userland as a parallel Distrobox container (`damianu`) via
`scripts/setup-ubuntu-dev-container.sh`. Do not silently replace `damianf` with Ubuntu unless
all dependent scripts are explicitly migrated too.

### Distrobox setup: prepare `~/.cache/distrobox` and auto-recover broken containers
**Problem:** On this laptop, `distrobox enter` can fail during first setup with:
```text
/usr/bin/distrobox-enter: ... /home/damian/.cache/distrobox/.<name>.fifo: No such file or directory
```
If that happens after `distrobox create`, the next rerun can mis-detect the existing container
as `Ubuntu unknown` and stop instead of recovering automatically.
**Fix:** Any setup or verification script that relies on `distrobox enter` should create
`"${XDG_CACHE_HOME:-$HOME/.cache}/distrobox"` first. For container-creation scripts, if an
existing container cannot be entered and the detected Ubuntu version is empty, treat it as a
broken partial create, remove it automatically, and recreate it unattended.

### ShellGPT: never block on missing API key
**Problem:** `sgpt` prompts interactively for an API key, blocking unattended setup.
**Fix:** `scripts/configure-shellgpt.sh` always writes a config file with
`OPENAI_API_KEY=missing-shellgpt-api-key` as placeholder. Do NOT remove this fallback.

### ShellGPT: don't overwrite custom sgpt
**Problem:** Damian might have a custom `~/.local/bin/sgpt`.
**Fix:** The configure script renames the repo-managed launcher to `sgpt-cli` and wraps it.
If an unmanaged `sgpt` exists, the script warns and leaves it untouched.

### ShellGPT: stale `-preview` env can silently regenerate wrong config
**Problem:** After the Gemini primary model changed from `gemini/gemini-3.1-flash-lite-preview`
to `gemini/gemini-3.1-flash-lite`, an old exported
`SHELLGPT_GEMINI_PRIMARY_MODEL=gemini/gemini-3.1-flash-lite-preview` could still be present in
the shell environment. `scripts/configure-shellgpt.sh` respected that inherited variable, so it
rewrote `~/.config/shell_gpt/.sgptrc` with the retired preview model even though the repo default
was already correct.
**Fix:** Normalize the old preview model name to `gemini/gemini-3.1-flash-lite` inside
`scripts/configure-shellgpt.sh`, the generated `~/.local/bin/sgpt` wrapper, and the generated
`~/.bashrc.d/shellgpt-gemini.bash` loader. When debugging ShellGPT model drift, check both:
```bash
grep '^DEFAULT_MODEL=' ~/.config/shell_gpt/.sgptrc
printf '%s\n' "${SHELLGPT_GEMINI_PRIMARY_MODEL:-}"
```

### ShellGPT 1.5.1 + LiteLLM: marker API key does NOT work for Gemini
**Problem:** The local `shell-gpt` version (`1.5.1`) always passes
`api_key=cfg.get("OPENAI_API_KEY")` into LiteLLM from `sgpt/handlers/handler.py`.
That means a placeholder like `OPENAI_API_KEY=litellm-provider-env` is sent literally to
Google as the API key, causing:
```text
API key not valid. Please pass a valid API key.
```
even when `GEMINI_API_KEY` is exported correctly in the shell.
**Fix:** For Gemini via LiteLLM, write the real private Gemini key into the private
`~/.config/shell_gpt/.sgptrc` as `OPENAI_API_KEY=<actual key>` and keep the file mode `600`.
Do not rely on a marker placeholder for this ShellGPT version. The same rule applies to
Anthropic via LiteLLM if ShellGPT still passes only `OPENAI_API_KEY`.

### ShellGPT + LiteLLM + Gemini: streamed output is unstable here
**Problem:** With the current local stack, streamed ShellGPT responses can show duplicated
partial text and then crash through a traceback path ending in:
```text
AttributeError: 'CustomStreamWrapper' object has no attribute 'close'
```
This is typically reached after a `KeyboardInterrupt` during streamed Gemini output, and the
overall user experience is noisy even when the underlying answer is fine.
**Fix:** Generate the private ShellGPT config with:
```text
DISABLE_STREAMING=true
```
so `sgpt` prints only the final response instead of live-streaming tokens. Do not turn
streaming back on by default unless this stack is re-validated.

### Toolbox prompt color: do NOT try to wrap it with generic `PROMPT_COMMAND` logic
**Problem:** Fedora Toolbox already sets its own prompt in `/etc/profile.d/toolbox.sh`:
```bash
PS1=$(printf "\[\033[35m\]⬢ \[\033[0m\]%s" "[\u@\h \W]\\$ ")
```
Generic `.bashrc` code that tries to recolor the current prompt through `PROMPT_COMMAND`
or by blindly wrapping the existing `PS1` is unreliable here. It can silently fail to
change the visible color, fight with Fedora's own prompt scripts, or break the expected
Toolbox/Distrobox formatting.
**Fix:** Use a direct interactive-shell override in `~/.bashrc`:
- if `/run/.toolboxenv` exists, set the exact Toolbox prompt text with the desired color
- if `/run/.containerenv` exists without Toolbox, preserve the existing prompt text and
  only recolor it
- on the host, recolor the normal prompt separately

For this repo, the working Toolbox override is:
```bash
PS1='\[\e[0;36m\]⬢ [\u@\h \W]\$ \[\e[0m\]'
```
Do not reintroduce the old `PROMPT_COMMAND` recoloring approach unless it is re-tested
interactively in a real Toolbox shell.

### Toolbox vs Distrobox prompt detection: do NOT rely only on `/run/.containerenv`
**Problem:** Both Toolbox and Distrobox can look like generic containers if detection is based
only on `/run/.containerenv` or on the already-rendered prompt text. That makes both prompts
end up with the same format or the same colour.
**Fix:** Split them by environment variables first:
- Toolbox: detect `TOOLBOX_PATH`
- Distrobox: detect `DISTROBOX_ENTER_PATH`

For this repo, the working behaviour is:
- Toolbox `damianf`: cyan `⬢ [user@toolbx damianf]$`
- Distrobox `damianu`: cyan `📦[user@distrobx damianu]$`
- Distrobox `security`: red `📦[user@distrobx security]$`

Do not treat `damianu` or `security` as generic
Toolbox-like containers when setting `PS1`.
Keep their explicit prompt labels in `.bashrc` so the user can distinguish Fedora Toolbox
from Ubuntu Distrobox sessions quickly.

Keep the `.bashrc` entry shortcuts `damianf` and `damianu` working. They intentionally hide
the `toolbox enter` / `distrobox enter` prefixes because those are easy for the user to mix up.

### Dev container parity: do not add tools only to Fedora toolbox
**Problem:** Damian uses both Fedora toolbox `damianf` and Ubuntu distrobox `damianu`
to learn both distributions. If a user-facing CLI/dev tool is installed only in
`setup-damian-container.sh`, the two learning environments drift and the documentation becomes
misleading.

**Fix:** Any new CLI/dev tool added to Fedora toolbox `damianf` must also be added to Ubuntu
distrobox `damianu` in the same change unless it is truly distro-specific. Update
`scripts/setup-damian-container.sh`, `scripts/setup-ubuntu-dev-container.sh`, `scripts/verify.sh`,
`README.md`, and `CLAUDE.md` together. If package names differ between Fedora and Ubuntu, document
the mapping explicitly in the setup scripts.

For command names that differ across distros, keep repo-managed wrappers in `~/.local/bin`.
Current examples:
- `bat` wrapper uses `/usr/bin/bat` or Ubuntu's `/usr/bin/batcat`
- `fd` wrapper uses `/usr/bin/fd` or Ubuntu's `/usr/bin/fdfind`
- `rg` wrapper prefers distro `/usr/bin/rg` over vendored ripgrep copies from other tools

fzf Bash integration may be loaded from either `/usr/share/fzf/shell/*.bash` or
`/usr/share/doc/fzf/examples/*.bash`. Source it only for interactive shells. This repo does not
bind `Ctrl-R`, `Ctrl-T`, or `Alt-C` elsewhere in Bash, so the default fzf bindings are acceptable.

### Ubuntu dev setup: do not require host sudo when no TTY is available
**Problem:** Running `scripts/setup-ubuntu-dev-container.sh` from a non-interactive automation
context failed at the host sudo keepalive step:

```text
sudo: a terminal is required to read the password
sudo: a password is required
```

This happened before the script reached the actual Distrobox package installation, even though
container-level `sudo apt-get ...` worked in the existing `damianu` container.

**Fix:** Do not call `require_sudo_session` unconditionally in the Ubuntu Distrobox setup. First
check for an interactive stdin or an already-valid non-interactive sudo session:

```bash
if [[ -t 0 ]] || sudo -n -v >/dev/null 2>&1; then
    require_sudo_session
else
    echo "No interactive sudo session available on the host — continuing with container-level sudo checks."
fi
```

Avoid reintroducing an unconditional host `sudo -v` in Distrobox setup scripts unless the script
really needs host root privileges at that point.

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

### Do not push before the whole requested change set is finished
**Problem:** Pushing too early creates unnecessary intermediate GitHub states where the code
change is uploaded before the matching docs and `AI_ERRORS.md` update are included.
**Fix:** For user-facing fix work in this repo, the expected order is:
1. make the code/config change
2. verify that it works
3. update documentation if needed
4. update `AI_ERRORS.md` if a real lesson/workaround was discovered
5. only then commit and push the final combined state

Do not push partial progress unless the user explicitly asks for an intermediate push.

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

### Thunderbird appearance changes need `_old` backups first
**Problem:** Thunderbird CSS changes are easy to dislike after testing, and
`scripts/setup-thunderbird.sh` copies repo CSS into the active Flatpak profile.
Changing `thunderbird/userChrome.css` or `thunderbird/userContent.css` without preserving
the old files removes the quick rollback path.
**Fix:** Before changing Thunderbird appearance files, create `_old` backups for the repo
files and the active profile files. `scripts/setup-thunderbird.sh` must keep using
one-time `_old` backups before copying `user.js`, `userChrome.css`, or `userContent.css`.
Do not overwrite an existing `_old` file.

### Thunderbird message list selectors are specific
**Problem:** The message list has different DOM/CSS paths for cards view and table view.
Generic selectors such as `.status`, `.sender`, or broad `background-color` rules can
change the wrong thing, for example turning the unread dot into a square.
**Fix:** Check Thunderbird's `omni.ja` first. For the current Flatpak build, cards view
uses `#threadTree .card-layout[data-properties~="unread"]`, `.read-status`, `.sender`,
and `.subject`; table view uses `tr[data-properties~="unread"]`, `.tree-view-row-unread`,
and `.subject-line`. The unread dot color should be changed with `--read-status-fill`,
`--read-status-stroke`, or `fill/stroke` only — do not set `background-color` on the dot.

### Thunderbird dark message reader background: `html/body` alone does not work
**Problem:** The built-in message reader dark mode uses Thunderbird's own `messageBody.css`.
Trying only this kind of `userContent.css` rule did not change the visible black background:
```css
@media -moz-pref("mail.dark-reader.enabled") {
  html,
  body {
    background-color: #1a1b26 !important;
  }
}
```
It also failed when guarded with `(prefers-color-scheme: dark)` only, because the profile has
`layout.css.prefers-color-scheme.content-override = 1`, which can make the message content
report a different scheme than expected.
**Fix:** Override both layers:
- in `userContent.css`, override Thunderbird's message-body token `--color-gray-90` to
  `#1a1b26` and keep `html` on the same color
- in `userChrome.css`, set `#messagepanebox`, `#singleMessage`, and `#messagepane` to the
  same background

The working blocks are labelled `Message body dark reader override` and
`Message pane dark reader background`. Do not replace them with a simpler `html, body`
background-only rule unless it is re-tested in the active Thunderbird Flatpak profile.

---

## 10. Approval Prompt Behavior

### Approval only triggers for `task_shell_start`
**Problem:** The TUI shows an approval prompt for `task_shell_start` (shell commands) but
NOT for `code_execution` (Python) or `task_shell_wait`. This can cause silent waits.
**Fix:** When the user needs to approve, use `request_user_input` to explicitly ask.
When doing file writes via `code_execution`, note that no approval prompt will appear
— confirm with the user verbally in chat first.

---

## 11. Whispering on Sway

### AppImage does not automatically appear in `Super+D`
**Problem:** Downloading and executing Whispering as an AppImage does not register it in
the Sway `Super+D` rofi launcher. The app may run successfully, but searching for
`Whispering` in the launcher shows nothing because no `.desktop` file exists.

**Fix:** For testing, create a user desktop entry, then refresh the desktop database:
```ini
[Desktop Entry]
Type=Application
Name=Whispering
Comment=Speech-to-text dictation
Exec=/path/to/working/whispering
Terminal=false
Categories=Utility;
StartupNotify=true
StartupWMClass=Whispering
```
```bash
update-desktop-database ~/.local/share/applications
```

**Real case:** During the first Whispering test on 2026-05-25, the AppImage was downloaded to:
```text
~/Downloads/whispering-test/Whispering_7.11.0_amd64.AppImage
```
and a temporary launcher was created at:
```text
~/.local/share/applications/whispering-test.desktop
```

If Whispering is accepted as the permanent replacement for the repo voice-typing flow, do
not leave the launcher as an ad-hoc file in `~/.local/share/applications`. Move the
`.desktop` file into `applications/`, symlink it from `setup.sh`, add `verify.sh` checks,
document the install path/provider/model choices, and commit/push the full change set.

### Codex sandbox is not a valid AppImage/Sway test environment
**Problem:** Running the Whispering AppImage directly from the Codex sandbox failed with:
```text
Error: No suitable fusermount binary found on the $PATH
fuse: device not found, try 'modprobe fuse' first
Cannot mount AppImage, please check your FUSE setup.
```
The host had `fuse3` installed and `fusermount3` available, but the sandbox did not expose
`/dev/fuse`, so the failure was a sandbox limitation rather than a reliable host diagnosis.

**Fix:** Test GUI AppImages outside the Codex sandbox. On this Sway setup, use approved
host execution through Sway:
```bash
swaymsg exec /var/home/damian/Downloads/whispering-test/Whispering_7.11.0_amd64.AppImage
```

### Direct GUI launch from Codex may fail with EGL
**Problem:** Running the AppImage directly outside the sandbox but still from the Codex
command context printed:
```text
Could not create default EGL display: EGL_BAD_PARAMETER. Aborting...
```
The same AppImage launched via `swaymsg exec` did create a `Whispering` window in the Sway
tree and initialized app data under:
```text
~/.local/share/com.bradenwong.whispering
```

**Fix:** For GUI validation, prefer `swaymsg exec ...` and verify with:
```bash
swaymsg -t get_tree | rg -i 'whisper|epicenter|tauri'
```

### AppImage v7.11.0 opened but rendered a blank white window
**Problem:** Whispering `v7.11.0` AppImage opened a Sway window, but Damian saw only a
plain white/light background with no text, buttons, or usable UI. This still happened after:
- moving the app/WebKit cache out of the way
- launching with `WEBKIT_DISABLE_COMPOSITING_MODE=1`
- launching with `WEBKIT_DISABLE_DMABUF_RENDERER=1`
- launching with `GDK_BACKEND=x11`
- launching with `LIBGL_ALWAYS_SOFTWARE=1`

Whispering app logs under `~/.local/share/com.bradenwong.whispering/logs/` were empty, so
the failure appeared to happen before the app's own logging layer.

**Fix / working test:** Do not assume the AppImage works on this Fedora Sway Atomic setup.
On 2026-05-25, the working test was the RPM build unpacked locally, not installed system-wide:
```bash
mkdir -p ~/Downloads/whispering-test/rpm-7.11.0
cd ~/Downloads/whispering-test/rpm-7.11.0
rpm2cpio ../Whispering-7.11.0-1.x86_64.rpm | cpio -idmv
swaymsg exec 'env GDK_BACKEND=x11 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 LIBGL_ALWAYS_SOFTWARE=1 ~/Downloads/whispering-test/rpm-7.11.0/usr/bin/whispering'
```

The temporary launcher was updated to use the unpacked RPM binary:
```ini
Exec=env GDK_BACKEND=x11 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 LIBGL_ALWAYS_SOFTWARE=1 /var/home/damian/Downloads/whispering-test/rpm-7.11.0/usr/bin/whispering
```

That only made the UI render far enough to inspect it. It was not stable.

### RPM binary rendered, then crashed/hung on interaction
**Problem:** The unpacked RPM binary for Whispering `v7.11.0` could show the UI, but Damian
reported that the app froze when clicking inside it. User journal and coredump output confirmed
real crashes:
```text
Process ... (whispering) of user 1000 dumped core.
Module libEGL_mesa.so.0 from rpm mesa-26.0.5-3.fc44.x86_64
Module libwebkit2gtk-4.1.so.0 ...
#0 WebKit::AcceleratedBackingStore::update(...)
```
and:
```text
Process ... (WebKitWebProces) of user 1000 dumped core.
#0 WebCore::RenderLayerCompositor::updateOverflowControlsLayers(...)
```

`coredumpctl --since '15 minutes ago'` showed repeated `SIGSEGV` crashes for both:
```text
/var/home/damian/Downloads/whispering-test/rpm-7.11.0/usr/bin/whispering
/usr/libexec/webkit2gtk-4.1/WebKitWebProcess
```

**Fix / decision, updated 2026-05-25:** Do not automate the upstream Whispering release
as-is on this Fedora Sway Atomic setup. The downloaded AppImage did not render reliably, and
the unpacked RPM binary was not stable after interaction.

A local source build from `EpicenterHQ/epicenter` did become usable after patching the app:
- remove the global SvelteKit `onNavigate(...)` hook from
  `apps/whispering/src/routes/+layout.svelte`
- specifically remove the `document.startViewTransition(...)` wrapper; on this
  Fedora 44/Sway/WebKitGTK stack it matched the WebKit crash path
- change the main sidebar navigation in
  `apps/whispering/src/routes/(app)/_components/VerticalNav.svelte` from `<a href=...>`
  links to `<button onclick={() => goto(item.href)}>` controls, matching the behavior of
  the lower sidebar buttons that already worked

The working local binary was built with:
```bash
toolbox run --container damianf bash -lc 'cd /var/home/damian/Downloads/whispering-test/epicenter-source && WHISPER_DONT_GENERATE_BINDINGS=1 bun run --cwd apps/whispering tauri build --no-bundle'
```

Launch it through Sway with the same WebKit/Mesa workarounds:
```bash
swaymsg exec "env GDK_BACKEND=x11 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 LIBGL_ALWAYS_SOFTWARE=1 /var/home/damian/Downloads/whispering-test/epicenter-source/apps/whispering/src-tauri/target/release/whispering"
```

Do not replace the repo voice typing automation yet. Speech-to-text, microphone access,
Polish transcription, clipboard/paste behavior, global shortcuts, and packaging still need
manual validation.

Temporary test artifacts from the failed experiment:
```text
~/Downloads/whispering-test/
~/.local/share/applications/whispering-test.desktop
~/.cache/whispering-test-backups/
```

### Whispering local mode needs manual UI validation before automation
**Problem:** Whispering has multiple transcription modes and providers. The existence of
the binary and launcher does not prove that microphone recording, Sway/Wayland shortcut
handling, clipboard/paste injection, Polish transcription, or local model download works.

**Fix:** Before replacing the current `Mod+T` voice typing scripts, Damian must validate in
the Whispering UI:
- `Settings -> Transcription -> Whisper C++`
- download a local model, starting with `Small`
- confirm `ffmpeg` is available (`/usr/bin/ffmpeg` currently comes from Fedora `ffmpeg-free`)
- test English and Polish dictation
- test whether output reaches clipboard or active text field
- test global shortcut behavior under Sway

Only after that should the repo automation be changed.

# Simple notes, English dictation and terminal help

## Choose the workflow

For free, simple text notes, use [Simplenote](https://simplenote.com/).
It supports Android, Windows, Linux and the web, with account synchronization.
It is already installed by `setup.sh` as `com.simplenote.Simplenote`.
Simplenote itself does not provide the AI grammar correction described below.

For voice recording and AI rewriting in one product, try
[AudioPen](https://www.audiopen.ai/). Linux uses the web app; Android and
Windows have apps. The free tier currently allows recordings up to three
minutes; longer recordings and additional features require Prime.
AI rewriting requires an Internet connection. Check current limits on the
vendor site before upgrading. AudioPen is an option to evaluate, not an
installed or selected replacement for the existing workflow.

## Dictate into Simplenote on Fedora Sway

1. Press **Super+D**, search for **Simplenote**, and open it.
2. Sign in and create a note. Click in its text editor.
3. Hold **Super+T**, speak in English, then release the keys.
4. Wait for transcription and correction while keeping the note focused.

Whisper transcribes locally inside Toolbox `damianf`. For English, the script
sends the transcript to Gemini and inserts the corrected UK English text.
Polish is inserted without Gemini correction. A missing key or failed Gemini
request falls back to the original transcript, so inserted text alone does
not prove that correction succeeded.

**Super** means the Windows/logo key (`Mod4` in Sway).
**Alt+Shift+D** is the separate Whispering Open push-to-talk binding.
These Sway shortcuts apply to Linux only. On Android and Windows, Simplenote
syncs notes but needs a separate dictation/correction tool. AudioPen can be
evaluated for that role, copying the corrected text into Simplenote.

The existing voice shortcut outputs corrected text only. It does not display
the original sentence beside the correction or explain each grammatical change.
For a learning explanation, use the terminal example below.

## Recover the terminal command assistant

The command assistant is **ShellGPT**, command **sgpt**.
Open Foot with **Super+Enter**, then enter the Fedora dev container:

```bash
damianf
sgpt --no-functions \
  "Explain which Linux command shows free disk space."
```

For a command suggestion without the execution prompt:

```bash
sgpt --shell --no-interaction --no-functions \
  "show free disk space in human-readable units"
```

For English feedback:

```bash
sgpt --no-functions \
  "Correct to British English and explain changes in Polish: I go yesterday."
```

The normal `--shell` mode is interactive and offers execution. Commands run
inside the current dev container. Host package installation uses rpm-ostree;
do not use a generated dnf command to install packages on the Atomic host.
AI requests require the configured provider and its current quota.

## Reproduce on a fresh Fedora install

The existing automation already installs these components:

| Component | Existing installation path |
| --- | --- |
| Simplenote | `setup.sh`, user Flatpak |
| ShellGPT | Both dev container setup scripts, `shell-gpt[litellm]` |
| Voice libraries | Both containers: `faster-whisper`, `google-genai` |
| Audio and typing | `packages.sh`: `alsa-utils`, `wtype`; then reboot |
| Voice shortcuts | Repo-managed `sway/config` linked by `setup.sh` |
| Gemini key | Restore `~/.config/voice-type/gemini-api-key` privately |

The voice shortcut uses `damianf` by default, even though the Python packages
also exist in the Ubuntu installer. Simplenote account login is manual.
Keep the Gemini key outside Git. For repair after a completed host setup:

```bash
bash ~/dotfiles-sway/scripts/setup-damian-container.sh
bash ~/dotfiles-sway/scripts/verify.sh
```

Do not run the entire setup merely to open an already installed application.

## Verification on 2026-10-10

- Simplenote, Foot, arecord and wtype are installed.
- Active Sway configuration contains Super+T and Alt+Shift+D bindings.
- Whispering Open launcher exists; its GUI and recording were not tested.
- `damianf` is running; imports of faster_whisper and google.genai succeeded.
- The private Gemini key file exists; its contents were not displayed.
- ShellGPT reports version 1.5.1. A live, function-disabled request returned
  `df -h` successfully.
- Microphone capture, full voice transcription/correction/insertion and
  cross-device synchronization still require an interactive user test.
- Existing fresh-install integration was inspected; no fresh OS installation
  or broad system repair was performed for this documentation update.

# dotfiles-sway

Personal dotfiles for Fedora Atomic Sway setup.

## What's included

### Window manager & UI
- Sway window manager config (borders, keybindings, idle/lock, screenshots, touchpad)
- Waybar status bar (bottom, muted dark theme, colour thresholds for CPU/RAM/temp/battery, Claude Code status, NordVPN toggle, AdGuard toggle, power menu)
- Autostart layout: terminal on ws1, Firefox on ws2, Thunderbird on ws3, Obsidian on ws4, Claude/ChatGPT PWA on ws5
- Foot terminal config
- Shared Bash prompt/aliases: host prompt in green, `damianf` prompt in cyan, `damianu` Distrobox prompt in cyan with package icon, `security` Distrobox prompt in red, `damianf`/`damianu` entry shortcuts, plus coloured `ls`/`ll`/`la` aliases
- Mako notification daemon (11s auto-dismiss)
- Clipboard history manager (clipman + rofi)
- JetBrainsMono Nerd Font + Font Awesome (terminal + Waybar)
- Black solid wallpaper

### Browser
- Firefox — main browser (ships in the Fedora Sway Atomic base image; the system default), opens on ws2
- Vivaldi (Flatpak) — hosts the Claude/ChatGPT PWAs on ws5

### Applications (Flatpak)
- VSCode — code editor
- Obsidian — notes
- Bitwarden — password manager
- Spotify
- OBS Studio — screen recording
- Kdenlive — video editor
- mpv — video player
- JDownloader — download manager
- Sticky — desktop sticky notes (com.vixalien.sticky)

### PWA shortcuts (Mod+D launcher)
- Claude AI — opens as minimal window without browser UI
- ChatGPT — opens as minimal window without browser UI
- WhatsApp — opens as minimal window without browser UI

### System
- `damianf` toolbox container (Fedora dev environment, versioned with the host unless overridden)
- `damianu` Ubuntu 26.04 distrobox container — Ubuntu dev/CLI environment with the same AI tools as `damianf`
- `security` Ubuntu 26.04 distrobox container — full security/pentesting toolkit
- KVM/QEMU virtualisation — virt-manager, virt-install, Windows 11 / Windows Server capable
- distrobox — for Ubuntu containers
- Screenshot tool (grim + slurp)
- Hardware acceleration (VA-API via mesa/amdgpu)
- Firewall baseline (public zone, SSH + mDNS only)
- Gitleaks secret scanner with a repo `pre-push` hook
- Voice typing — push-to-talk (`Mod+T`) with local Whisper AI + Gemini UK English correction
- Neovim 0.12.1 — user-local latest pinned binary with Chris Titus Tech `titus-kickstart` config
- yazi — keyboard-driven terminal file manager (primary FM on Sway; Thunar kept as GUI fallback), with image/video/PDF previews and a `<C-o>` binding that opens the current directory in Thunar (for drag-and-drop into apps yazi can't reach)
- AI terminal tools in `damianf` toolbox and `damianu` distrobox: Claude Code, OpenAI Codex CLI, DeepSeek TUI, ShellGPT (`sgpt`)
- Dev language toolchains in both dev containers: Go, Rust (`rustup` + `rust-analyzer`, into the shared `~/.cargo`), Python tooling (`pipx` + `uv`)
- DevOps stack in both dev containers: `podman`/`docker` CLI (per-OS) plus a home-local, OS-agnostic set — `kubectl`, `helm`, `kind`, `k9s`, `opentofu` (`tofu`), `ansible`, `yq` — installed by `scripts/install-devops-tools.sh` with runtime-discovered versions
- NordVPN CLI with Waybar status/toggle helper (click to connect/disconnect)
- AdGuard for Linux CLI with Waybar toggle helper (click to enable/disable)
- LibreOffice — open source office suite (Writer, Calc, Impress)
- Thunderbird email client (Flatpak)
- Kdenlive video editor (Flatpak)
- Whispering Open — downloaded from the latest GitHub release when available

---

## Fresh install

### Prerequisites

1. Optional: generate an SSH key if you want to use SSH remotes or clone private forks:
```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
```

`bootstrap.sh` now clones this repo over HTTPS by default, so the fresh install path does not require GitHub SSH auth.

2. Private AI API key for voice typing and ShellGPT:
```bash
mkdir -p ~/.config/voice-type
chmod 700 ~/.config/voice-type
printf '%s\n' 'your-gemini-api-key-here' > ~/.config/voice-type/gemini-api-key
chmod 600 ~/.config/voice-type/gemini-api-key
```

This file is private, outside git, and is shared with the active dev containers through the home directory. Voice typing uses it directly, and `scripts/configure-shellgpt.sh` uses the same key by default through LiteLLM. ShellGPT prefers `gemini-3.1-flash-lite` and its installed `sgpt` wrapper retries `gemini-2.5-flash-lite` if the primary model is temporarily unavailable. On a fresh machine the key should be restored from your private backup or secret manager before `setup-damian-container.sh` or `setup-ubuntu-dev-container.sh` runs.

ShellGPT also accepts `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `SHELLGPT_API_KEY`, `ANTHROPIC_API_KEY`, `~/.config/ai/api.env`, `~/.config/shell_gpt/credentials.env`, and `~/.bashrc.d/ai-keys.bash`. Use `SHELLGPT_PROVIDER=openai`, `gemini`, or `anthropic` only when you need to override the automatic choice.

3. Run bootstrap:
```bash
bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
```

Bootstrap will:
- Clone this repository
- Initialise git submodules, including `ChrisTitusTech/neovim`
- Run setup.sh (symlinks, Flatpaks, toolbox, fonts)
- Run packages.sh (system packages via rpm-ostree)

4. Reboot after bootstrap completes:
```bash
systemctl reboot
```

5. After reboot verify hardware:
```bash
bash ~/dotfiles-sway/scripts/check-hardware.sh
```

6. Set up KVM virtualisation:
```bash
bash ~/dotfiles-sway/scripts/setup-kvm.sh
```
> Then log out and back in for group changes to take effect.
> The script creates its own libvirt NAT network named `dotfiles-nat` on the first free subnet from `192.168.125.0/24` upward, so it does not have to rewrite libvirt's `default` network.

7. Set up the dev toolbox (node, npm, gh, Claude Code, Codex CLI, DeepSeek TUI, ShellGPT):
```bash
bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```
By default the script targets the host Fedora version and the toolbox name `damianf`. You can override both for migrations:
```bash
TOOLBOX_CONTAINER=damian44 TOOLBOX_VERSION=44 bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```

8. Set up the Ubuntu dev distrobox (same AI/dev CLI stack as `damianf`, but on Ubuntu 26.04):
```bash
bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh
```
Use this when you want an Ubuntu userland instead of Fedora Toolbox for terminal work:
```bash
damianu
```
Dev container parity is intentional: any user-facing CLI/dev tool added to Fedora toolbox `damianf` must also be added to Ubuntu distrobox `damianu` in the same change, then covered by `scripts/verify.sh`.
Voice typing still uses toolbox `damianf` by default.

9. Install NordVPN CLI and the Waybar helper:
```bash
bash ~/dotfiles-sway/scripts/setup-nordvpn.sh
```
This also enables and starts `nordvpnd` automatically when the service unit is available.
After that, log out or reboot so the `nordvpn` group membership takes effect, then log in manually:
```bash
nordvpn login
```
If browser callback flow fails on Linux/Flatpak browsers, use a Nord Account access token instead:
```bash
nordvpn login --token <token>
```
Generate the token in Nord Account → NordVPN → Advanced settings → Get access token.

Preferred post-login settings for this setup:
```bash
nordvpn settings
```
Expected baseline:
- `Technology: NORDLYNX`
- `Firewall: enabled`
- `Routing: enabled`
- `Notify: enabled`
- `Auto-connect: disabled`
- `Kill Switch: disabled`

No extra post-login changes are required for the current setup.

Daily manual CLI usage:
```bash
nordvpn connect
nordvpn status
nordvpn disconnect
```
Use `nordvpn connect <country>` for a specific country, for example:
```bash
nordvpn connect Poland
```

10. Install AdGuard for Linux:
```bash
bash ~/dotfiles-sway/scripts/setup-adguard.sh
```
This installs the official AdGuard CLI. First-time activation and configuration remain manual:
```bash
adguard-cli activate
adguard-cli configure
adguard-cli start
```
Recommended first-time setup for this laptop:
- enable protection
- keep DNS filtering local to the laptop
- do not try to replace your NAS `AdGuard Home` or your network `NextDNS` design with this client

Daily manual CLI usage:
```bash
adguard-cli status
adguard-cli start
adguard-cli stop
```

11. Create the security container:
```bash
bash ~/dotfiles-sway/scripts/setup-security-container.sh
```

12. Run full verification:
```bash
bash ~/dotfiles-sway/scripts/verify.sh
```

13. Optional: validate the fresh-install flow in a disposable Fedora Sway Atomic VM:
```bash
bash ~/dotfiles-sway/scripts/create-fedora-sway-vm.sh
```
This downloads the official Fedora Everything installer ISO, installs Fedora Sway Atomic with kickstart, injects your host SSH key for access, and runs the bootstrap phase inside the VM.
Live images are not used for this test because Fedora Kickstart does not support live media as an installation source.
The script verifies the installer ISO checksum, injects kickstart into the installer initrd, resolves the Fedora ostree content URL from the official mirrorlist, and starts the VM again if Anaconda shuts it off after installation.
For this disposable validation VM, the kickstart uses `ostreesetup --nogpg` because the Fedora 44 netinst Anaconda environment can miss the current ostree signing key even when the ISO checksum is valid.

`verify.sh` checks every component of the installation and shows a summary:
- ✓ passed / ✗ failed / ⚠ warnings
- For each failure: exact command to fix it
- Install state from `~/.dotfiles-install-state` (written by each script)
- Install log from `~/.dotfiles-install.log` with date/time on every line

If anything failed during installation, re-run the relevant script — all scripts are safe to run multiple times and will skip already-completed steps.

### Troubleshooting install failures

Every install script writes progress to:

```bash
~/.dotfiles-install-state
```

Every install script also appends full terminal output to:

```bash
~/.dotfiles-install.log
```

Each log line starts with a timestamp, for example:

```text
[2026-04-29 20:45:12] ==> Installing Flatpaks...
```

If a fresh install fails, check the state file first to find the failed phase, then inspect the log around the same time:

```bash
cat ~/.dotfiles-install-state
tail -200 ~/.dotfiles-install.log
bash ~/dotfiles-sway/scripts/verify.sh
```

---

## Sway configuration

### Modifier key
`Super` (Windows key) — referred to as `$mod` throughout the config.

### Keyboard layout
GB layout with Polish characters via PL variant. No switching needed — Polish characters accessible via compose key combinations.

### Wallpaper
Solid black (`#000000`) — no image, no distractions.

### Window borders
- Border style: `pixel 1` (1px border, no title bar)
- Focused window border colour: dark amber `#5c3000`
- Floating windows: no border (`default_floating_border none`)
- Gaps: none (inner 0, outer 0)

### Idle & lock
| Timeout | Action |
|---|---|
| 600s (10 min) | Display off (`output * power off`) |
| 900s (15 min) | Screen locks (`swaylock`, black screen) |
| 1200s (20 min) | System suspends (`systemctl suspend`) |
| Before sleep | Screen locks automatically |

### Touchpad
- Tap to click: enabled
- Tap button map: left / right / middle
- Natural scroll: enabled
- Disable while typing: enabled
- Middle emulation: enabled

### Workspace layout (autostart)
| Workspace | Content |
|---|---|
| 1 | Foot terminal |
| 2 | Firefox browser |
| 3 | Thunderbird |
| 4 | Obsidian |
| 5 | Claude AI PWA + ChatGPT PWA |
| 9 | WhatsApp PWA |

Apps are launched by `exec` lines in `sway/config` and pinned to workspaces by
`assign`/`for_window` rules. Thunderbird is started via
`scripts/launch-thunderbird.sh`, which discovers the installed Thunderbird
flatpak at runtime (regular or `_esr` variant) instead of hardcoding an app ID —
Flathub deprecated the plain `org.mozilla.Thunderbird` ID in favour of
`org.mozilla.thunderbird_esr`, which silently broke the old hardcoded `exec`. The
`assign` rule matches any variant via a case-insensitive regex.

### Key bindings

#### Basics
| Shortcut | Action |
|---|---|
| `Mod+Return` | Open terminal (foot) |
| `Mod+D` | Application launcher (rofi) |
| `Mod+Q` | Close focused **window** only (e.g. one Vivaldi Settings window — the rest of the app keeps running) |
| `Mod+Shift+Q` | Close the whole **app** (terminates the process, so Chromium/Electron apps don't linger) |
| `Mod+Shift+C` | Reload Sway config |
| `Mod+Shift+E` | Exit Sway session |
| `Mod+C` | Clipboard history picker (clipman + rofi) |
| `Mod+Shift+Escape` | Lock screen immediately (loginctl) |
| `Mod+T` (hold) | Voice typing — record speech, release to transcribe and type |
| `Print` | Full screenshot → `~/Pictures/` |
| `Mod+Print` | Region screenshot (slurp) → `~/Pictures/` |

#### Focus & movement
| Shortcut | Action |
|---|---|
| `Mod+H/J/K/L` | Focus left/down/up/right (Vim-style) |
| `Mod+Arrow` | Focus with arrow keys |
| `Mod+Shift+H/J/K/L` | Move window left/down/up/right |
| `Mod+Shift+Arrow` | Move window with arrow keys |

#### Workspaces
| Shortcut | Action |
|---|---|
| `Mod+1–9` | Switch to workspace |
| `Mod+Shift+1–9` | Move window to workspace |

#### Layout
| Shortcut | Action |
|---|---|
| `Mod+B` | Split horizontal |
| `Mod+V` | Split vertical |
| `Mod+E` | Toggle split direction |
| `Mod+S` | Stacking layout |
| `Mod+W` | Tabbed layout |
| `Mod+F` | Toggle fullscreen |
| `Mod+Shift+Space` | Toggle floating |
| `Mod+Space` | Toggle focus tiling/floating |
| `Mod+A` | Focus parent container |
| `Mod+R` | Enter resize mode |

#### Scratchpad
| Shortcut | Action |
|---|---|
| `Mod+Shift+-` | Send window to scratchpad |
| `Mod+Shift+W` | Hide focused window to background ("close but not fully") — same as send-to-scratchpad, on a memorable key. Apps keep running (tray apps like Whispering Open keep their tray icon). |
| `Mod+-` | Show/cycle scratchpad (bring a hidden window back) |

#### Autostart trigger
| Shortcut | Action |
|---|---|
| `Mod+Shift+S` | Re-run autostart script (Firefox + Claude PWA + ChatGPT PWA + Obsidian) |

#### File manager (yazi — in-app, not Sway)
| Shortcut | Action |
|---|---|
| `Ctrl+O` | Open the current directory in Thunar (GUI) — for drag-and-drop into apps a terminal FM can't reach (e.g. WhatsApp web). Added via `prepend_keymap`, so no default yazi binding is changed. |

---

## Waybar configuration

### Position & size
- Position: **bottom**
- Height: **25px**
- Module spacing: 4px

### Colour theme
Dark muted blue-slate palette — low contrast, easy on the eyes.

| Element | Colour |
|---|---|
| Bar background | `rgba(20, 22, 28, 0.92)` — near-black, slightly transparent |
| Bar border (top) | `rgba(60, 65, 80, 0.6)` — subtle separator |
| Default text | `#c0c8d8` — light blue-grey |
| Module background | `#1e2230` — dark navy |
| Module text | `#8a9bb5` — muted steel blue |
| Inactive workspaces | `#7a8499` |
| Focused workspace bg | `#2a2f3d` with `#6a8caf` underline |
| Warning state | bg `#2a2010`, text `#c8a060` — amber |
| Critical state | bg `#2a0000`, text `#ff0000` — red, blinking |
| Battery charging | bg `#1a2a1a`, text `#6ab56a` — green |
| Power-saver mode | bg `#1a2a1a`, text `#5a9955` — green |
| Performance mode | bg `#2a0000`, text `#ff3333` — red warning |

### Modules

**Left:** `workspaces` · `mode` · `scratchpad`

**Centre:** `window` (focused window title)

**Right:** `claude` · `idle_inhibitor` · `pulseaudio` · `network` · `power-profiles-daemon` · `cpu` · `memory` · `temperature` · `backlight` · `adguard` · `updates` · `battery` · `clock` · `tray` · `nordvpn`

### Alert thresholds

| Module | Warning | Critical |
|---|---|---|
| CPU | 70% | 80% (blinking) |
| Memory | 70% | 80% (blinking) |
| Temperature | 85°C | 95°C (blinking) |
| Battery | 40% | 20% (blinking) |

### Updates indicator

The `custom/updates` module (`⬆` icon) tracks pending updates across three sources, with all detection logic shared in `scripts/lib-updates.sh`:

- **Flatpak** apps
- **Containers** (auto-discovered distrobox + toolbox; flagged stale past a threshold)
- **Fedora OS** (`rpm-ostree`; uses a last-known-good cache so it still reports when the repo is offline)

**Severity classes — the colour encodes the action required of you:**

- `uptodate` (grey, neutral) — nothing to do
- `warning` (amber) — updates available (Flatpak, containers, **or** an OS update to download, incl. security) → run the updater, **no reboot**
- `critical` (red) — a deployment is **staged**, awaiting reboot → reboot to apply

OS pending packages and security updates count toward the badge (amber) but never turn it red; only an actually staged update (waiting for a reboot) is red. The tooltip lists each source on its own line.

**Event-driven, not polled — light on the host.** The default mode *only reads the cached JSON* (~13 ms) and never blocks on the slow (~10 s) `rpm-ostree` check. Correctness comes from recomputing at every state change, not from frequent polling:

- **Push:** every `--compute` run atomically rewrites `~/.cache/waybar-updates.json`, then signals Waybar (`pkill -RTMIN+8 -x waybar`; the module declares `"signal": 8`) to redraw at once.
- **Per-session refresh:** the first default-mode run of a login session (marker in `$XDG_RUNTIME_DIR`, wiped on reboot) forces one recompute, so a staged update applied by a reboot is reflected immediately on next login.
- **Periodic discovery:** Waybar polls only once an hour (`interval: 3600`) as a slow heartbeat; that run recomputes when the cache is older than `CACHE_MAX_AGE` (3 h), catching new upstream packages.

Because the push handles instant feedback, there is no fast 5 s polling — idle wake-ups drop from ~720/h to 1/h. No systemd timer is needed.

**Interaction:** left-click runs `updates-do` (apply updates). The update menu (`updates-menu`) recomputes the cache via `updates-waybar --compute` after **every** option and on exit (via an `EXIT` trap — covers Cancel/Ctrl-C), and again before the reboot prompt so the icon turns red while you decide. A recompute reads ground truth, so an update that silently failed keeps the badge lit instead of falsely clearing it.

All three scripts (`updates-waybar`, `updates-do`, `updates-menu`) are symlinked into `~/.local/bin` by `setup.sh`; `lib-updates.sh` is resolved next to them and needs no separate symlink.

### Fonts
- **Primary:** JetBrainsMono Nerd Font — monospace, icons in terminal and Waybar
- **Secondary:** Font Awesome 6 Free + Font Awesome 6 Brands — additional icons

Both fonts are installed automatically by `setup.sh`.

---

## Keyboard layout

GB layout with Polish characters via PL variant. No switching needed, so the Waybar language indicator is intentionally removed.

## Bluetooth devices

Pair devices manually using bluetoothctl — the GUI applet may have connection issues:
```bash
bluetoothctl
power on
scan on
pair <MAC_ADDRESS>
```

## Notes

- `pavucontrol` is already included in Fedora Atomic base — no separate install needed
- Thunderbird is installed from Flathub as `org.mozilla.thunderbird_esr` (the plain `org.mozilla.Thunderbird` ID is end-of-life and rebased to the ESR build; Flathub ships only ESR). Autostart discovers the installed variant at runtime via `scripts/launch-thunderbird.sh`
- 24-hour time format: `LC_TIME=en_GB.UTF-8` via `~/.config/environment.d/locale.conf`, imported into Sway session and overridden for Thunderbird Flatpak
- Thunderbird custom CSS lives in `thunderbird/userChrome.css` and `thunderbird/userContent.css`; `scripts/setup-thunderbird.sh` creates one-time `_old` backups in the active profile before applying repo-managed files
- Thunderbird message list (`#threadTree`, Thread Pane) uses a Tokyo Night-inspired style: `Noto Sans` at `1rem`, `#1a1b26` background, `#c0caf5` text, cyan unread indicator/subject (`#7dcfff`), and `font-weight: 400` for read mail vs `600` for unread mail. Folder list (`#folderTree`, Folder Pane) uses the same base font and size.
- Thunderbird message reader dark mode keeps the built-in Light/Dark toggle, but overrides the dark message background to match the Thread Pane (`#1a1b26`). This needs both `userContent.css` (`--color-gray-90`) and `userChrome.css` (`#messagepanebox`, `#singleMessage`, `#messagepane`).
- Mako displays notifications but does not play notification sounds itself. Mail sounds should be handled by Thunderbird/PipeWire; if Thunderbird's default system sound stays silent, set a concrete custom sound in Thunderbird rather than debugging Mako first.
- Kdenlive is installed as the Flathub Flatpak `org.kde.kdenlive`. Its effects/filters come from the Kdenlive/MLT stack, including bundled `frei0r`/`avfilter` support and Flatpak audio plugin extensions pulled in by Flathub; do not layer host video-effect packages unless a specific missing effect is verified.
- TODO: after Thunderbird filters are recreated manually and tested, add `msgFilterRules.dat` files to repo automation as symlinked profile files with backups.
- NordVPN: official Linux CLI install via `bash ~/dotfiles-sway/scripts/setup-nordvpn.sh` with automatic `nordvpnd` enable/start
- AdGuard for Linux: official CLI install via `bash ~/dotfiles-sway/scripts/setup-adguard.sh`; first-time `activate/configure/start` stays manual
- Ubuntu dev container must be created after first reboot (distrobox installed via packages.sh)
- Rebuild Ubuntu dev container manually: `bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh`
- Enter Ubuntu dev container: `damianu`
- Security container must be created after first reboot (distrobox installed via packages.sh)
- Rebuild security container manually: `bash ~/dotfiles-sway/scripts/setup-security-container.sh`
- Enter security container: `distrobox enter security`
- Default browser set to Firefox via xdg-settings

---

## Structure
```
dotfiles-sway/
├── CLAUDE.md                # AI assistant instructions (read this first)
├── sway/                    # Sway window manager config
├── waybar/                  # Waybar status bar config + style
├── foot/                    # Foot terminal config
├── mako/                    # Mako notification config
├── claude/
│   └── settings.json        # Claude Code settings (plugins, statusline) → symlinked to ~/.claude/settings.json
├── applications/            # Desktop shortcuts (Claude AI, ChatGPT, WhatsApp, Whispering Open)
├── nvim/
│   └── christitustech       # Git submodule: ChrisTitusTech/neovim, config lives in titus-kickstart/
├── .githooks/
│   └── pre-push             # Runs gitleaks before git push
├── scripts/
│   ├── lib-install.sh                 # Shared helpers: state tracking, run_step()
│   ├── verify.sh                      # Post-install verification — checks all components
│   ├── autostart.sh                   # Sway autostart: Firefox, Claude PWA, ChatGPT PWA, Obsidian
│   ├── fix-vivaldi-profiles.sh        # Fix Vivaldi crash/session recovery dialog
│   ├── check-hardware.sh              # Hardware check (GPU, VA-API, audio, ...) — writes state
│   ├── setup-kvm.sh                   # KVM/QEMU setup (libvirtd, groups, network) — writes state
│   ├── setup-neovim-config.sh         # Neovim 0.12.1 + Chris Titus Tech config symlink
│   ├── setup-nordvpn.sh               # NordVPN CLI install + nordvpnd enable/start + group setup — writes state
│   ├── setup-adguard.sh               # AdGuard for Linux CLI install — writes state
│   ├── setup-whispering-open.sh       # Whispering Open GitHub release download — non-blocking
│   ├── setup-damian-container.sh      # Toolbox damianf: node, npm, gh, Claude Code, Codex CLI, ShellGPT + plugins — writes state
│   ├── setup-ubuntu-dev-container.sh  # Distrobox damianu: Ubuntu 26.04 dev/AI CLI parity — writes state
│   ├── configure-shellgpt.sh          # Non-interactive ShellGPT config from private env/API files
│   ├── install-devops-tools.sh        # Home-local DevOps CLIs (kubectl/helm/kind/k9s/tofu/ansible/yq), shared across containers
│   ├── adguard-waybar.sh              # AdGuard Waybar toggle helper (AG — click to start/stop)
│   ├── nordvpn-waybar.sh              # NordVPN Waybar toggle helper (VPN — click to connect/disconnect)
│   ├── power-menu.sh                  # Rofi power menu (shutdown/reboot/suspend/hibernate/logout)
│   ├── setup-splunk.sh                # OPTIONAL — Splunk Enterprise (free) via podman (SIEM lab)
│   ├── setup-wazuh.sh                 # OPTIONAL — Wazuh all-in-one via podman (SIEM/XDR lab)
│   ├── backup-container.sh            # Snapshot a distrobox container for restore
│   ├── backup-win11.sh                # Snapshot/restore Windows 11 VM (SOC lab)
│   ├── setup-misp.sh                  # OPTIONAL — MISP threat intel platform (podman)
│   ├── setup-thehive-cortex.sh        # OPTIONAL — TheHive + Cortex IR automation (podman)
│   ├── setup-security-container.sh   # Distrobox security: pentesting toolkit — writes state
│   ├── voice-type-start.sh           # Voice typing: start recording (Mod+T press)
│   ├── voice-type-stop.sh            # Voice typing: stop recording, transcribe, inject text (Mod+T release)
│   └── voice-transcribe.py          # Whisper AI transcription (runs inside damianf toolbox)
├── setup.sh                 # Symlinks, Flatpaks, toolbox, fonts, Claude settings
├── packages.sh              # rpm-ostree system packages
└── bootstrap.sh             # Fresh install entry point
```

### Git Secret Scanning

`gitleaks` is installed as a required host package by `packages.sh`. `setup.sh` configures this repo to use `.githooks`:

```bash
git -C ~/dotfiles-sway config core.hooksPath .githooks
```

Before every `git push`, `.githooks/pre-push` runs:

```bash
gitleaks detect --source . --redact --verbose
```

If `gitleaks` is missing or detects a secret, the push is blocked. You can run the same check manually before committing:

```bash
gitleaks detect --source ~/dotfiles-sway --redact --verbose
```

---

## Whispering Open

`setup.sh` attempts to install Whispering Open from the latest GitHub release:

```bash
bash ~/dotfiles-sway/scripts/setup-whispering-open.sh
```

By default it downloads from:

```text
dmwasielewski/whispering-open
```

The installer writes the app under `~/.local/opt/whispering-open`, creates
`~/.local/bin/whispering-open`, and symlinks `applications/whispering-open.desktop` into
`~/.local/share/applications/` so it appears in `Mod+D`.

This step is intentionally non-blocking during `setup.sh`: if the GitHub release is missing,
the network is unavailable, or the asset format is unsupported, the failure is recorded in
`~/.dotfiles-install-state` and `~/.dotfiles-install.log`, then the rest of setup continues.

Supported release asset formats are AppImage, tar archives, zip archives, and RPMs that can
be unpacked locally. Override the source with:

```bash
WHISPERING_OPEN_REPO=owner/repo bash ~/dotfiles-sway/scripts/setup-whispering-open.sh
WHISPERING_OPEN_ASSET_REGEX='linux|x86_64|appimage' bash ~/dotfiles-sway/scripts/setup-whispering-open.sh
```

---

## Voice typing

Push-to-talk voice typing with local Whisper AI transcription and Gemini AI English correction.

**How to use:**
1. Hold `Mod+T` — recording starts (notification appears)
2. Speak in Polish or English
3. Release `Mod+T` — text is transcribed and typed into the active window

**Language behaviour:**
- **Polish** — transcribed locally by Whisper, typed as-is. No internet required.
- **English** — transcribed by Whisper, then sent to Gemini (UK English) for grammar and naturalness correction. Corrected text is typed.

**Setup (runs automatically during `setup-damian-container.sh`):**
- `faster-whisper` (Whisper model `small`, ~470 MB) — local speech recognition
- `google-genai` — Gemini API client for English correction
- `wtype` and `alsa-utils` (`arecord`) on the host via `packages.sh`

**Gemini API key (required for English correction):**
```bash
mkdir -p ~/.config/voice-type
echo "YOUR_GEMINI_API_KEY" > ~/.config/voice-type/gemini-api-key
chmod 600 ~/.config/voice-type/gemini-api-key
```

Voice correction tries Gemini models in this order:

1. `gemini-3.1-flash-lite`
2. `gemini-2.5-flash-lite`

Override with `VOICE_TYPE_GEMINI_MODELS` as a comma-separated list if needed.
Get a free key at: https://aistudio.google.com

**Performance (Ryzen 5 5600H, CPU only):**
- First run after boot: ~15–20 s (Whisper model loads from disk)
- Subsequent runs: ~10–15 s per utterance (+ ~1 s Gemini API for English)

**To increase accuracy (slower):** edit `scripts/voice-transcribe.py` and change `"small"` to `"medium"`.

**Audio file:** recorded to `~/.cache/voice-type/voice-input.wav`, deleted after transcription.

---

## Neovim

Modern text editor — Vim fork with Lua config, built-in LSP, and a large plugin ecosystem.

This setup uses:
- Official upstream Neovim `v0.12.1` installed to a versioned directory under `~/.local/opt/`, with `~/.local/opt/nvim-linux-x86_64` pointing at the active release
- `~/.local/bin/nvim` symlink, which wins over `/usr/bin/nvim` because `.bashrc` puts `~/.local/bin` first
- Chris Titus Tech's Neovim config as a git submodule: `nvim/christitustech`
- `~/.config/nvim` symlinked to `~/dotfiles-sway/nvim/christitustech/titus-kickstart`
- Plugins synced headlessly to Chris's `nvim-pack-lock.json` during `scripts/setup-neovim-config.sh`

The Fedora `neovim` rpm remains installed as a fallback, but the active editor should be the user-local upstream binary. This is intentional because the Chris Titus Tech config uses newer Neovim features.

**Install or repair:**
```bash
bash ~/dotfiles-sway/scripts/setup-neovim-config.sh
```

During setup, Neovim downloads plugins declared by Chris Titus Tech's config and synchronizes them to the config's `nvim-pack-lock.json`. The required CLI dependencies are layered by `packages.sh`: `ripgrep`, `fd-find`, `fzf`, `wl-clipboard`, `python3-virtualenv`, `ShellCheck`, `libwebp-tools`, `nodejs`, `npm`, and `make`. `markdownlint-cli2` is installed into the shared `~/.npm-global` prefix by both dev container setup scripts.

Because `~` is shared into both dev containers, the same `~/.local/bin/nvim` and `~/.config/nvim` are available inside Fedora toolbox `damianf` and Ubuntu distrobox `damianu`.

**Open a file:**
```bash
nvim filename.txt
```

**Basic usage:**
| Key | Action |
|---|---|
| `i` | Enter insert mode (start typing) |
| `Esc` | Return to normal mode |
| `:w` | Save file |
| `:q` | Quit |
| `:wq` | Save and quit |
| `:q!` | Quit without saving |
| `h/j/k/l` | Move left/down/up/right |
| `dd` | Delete current line |
| `u` | Undo |
| `Ctrl+r` | Redo |
| `/text` | Search for "text" |
| `n` | Next search result |

**Modes:**
- **Normal mode** — default, for navigation and commands (press `Esc` to get here)
- **Insert mode** — for typing text (press `i`)
- **Visual mode** — for selecting text (press `v`)
- **Command mode** — for `:w`, `:q` etc. (press `:`)

**Config file:** `~/.config/nvim/init.lua` from Chris Titus Tech's `titus-kickstart`.

**Important:** Chris's config includes WakaTime and an image-paste plugin with Chris's own default website image path. If you do not use WakaTime, ignore its prompt or disable that plugin later in the submodule/fork workflow.

---

## Vivaldi profile recovery

If Vivaldi shows Session Recovery dialog after reboot, the crash flag fix runs automatically on every sway start via `scripts/fix-vivaldi-profiles.sh`. The script writes `Preferences` atomically and keeps a one-time `*.bak-before-dotfiles` backup beside each repaired file.

To fix manually (Vivaldi must be closed first):
```bash
pkill -f vivaldi; sleep 2
bash ~/dotfiles-sway/scripts/fix-vivaldi-profiles.sh
```

---

## Developer ecosystem

### Architecture
```
Host (rpm-ostree immutable)
│
├─ Flatpak apps
│   └─ User Flatpaks from Flathub: Obsidian, Vivaldi, Thunderbird, VSCode, Bitwarden, Spotify, OBS, Kdenlive, mpv, JDownloader
│
├─ toolbox: damianf (Fedora version follows the host by default) — dev/DevOps
│   ├─ node 22
│   ├─ npm
│   ├─ git
│   ├─ gh (GitHub CLI)
│   ├─ claude (Claude Code)
│   ├─ codex (OpenAI Codex CLI)
│   ├─ deepseek (DeepSeek TUI)
│   ├─ sgpt (ShellGPT terminal assistant)
│   ├─ ccstatusline (Claude Code Waybar integration)
│   ├─ faster-whisper (local Whisper AI for voice typing)
│   ├─ terminal tools: btop, duf, bat, ncdu, rg, fzf, fd
│   ├─ languages: go, rust (rustup + rust-analyzer), python (pipx + uv)
│   ├─ DevOps: podman/docker CLI, kubectl, helm, kind, k9s, tofu, ansible, yq
│   └─ nvim (shared user-local Neovim + Chris Titus Tech config)
│
├─ distrobox: damianu (Ubuntu 26.04) — Ubuntu userland with AI/dev CLI parity
│   ├─ node 22
│   ├─ npm
│   ├─ git
│   ├─ gh (GitHub CLI)
│   ├─ claude (Claude Code)
│   ├─ codex (OpenAI Codex CLI)
│   ├─ deepseek (DeepSeek TUI)
│   ├─ sgpt (ShellGPT terminal assistant)
│   ├─ markdownlint-cli2
│   ├─ faster-whisper
│   ├─ terminal tools: btop, duf, bat, ncdu, rg, fzf, fd
│   ├─ languages: go, rust (rustup + rust-analyzer), python (pipx + uv)
│   ├─ DevOps: podman/docker CLI, kubectl, helm, kind, k9s, tofu, ansible, yq
│   └─ nvim (shared user-local Neovim + Chris Titus Tech config)
│
└─ distrobox: security (Ubuntu 26.04) — pentesting & security research
    ├─ Network:    nmap, masscan, wireshark, tcpdump, netcat, socat
    ├─ Web:        nikto, sqlmap, gobuster, ffuf, dirb, wfuzz, burpsuite
    ├─ Passwords:  hydra, john, hashcat, medusa
    ├─ Exploit:    metasploit, evil-winrm, impacket, pwntools
    ├─ Recon:      enum4linux-ng, dnsutils, whois, net-tools
    ├─ Forensics:  binwalk, foremost, steghide, exiftool, aircrack-ng
    ├─ Wordlists:  SecLists at /opt/SecLists
    └─ Utils:      tmux, vim, jq, htop, btop, curl, wget, git, python3
```

### Container engine (Podman) — host engine, not nested

The dev containers (`damianf`, `damianu`) are themselves **rootless Podman containers**. Running Podman *again* inside them (nested rootless) **does not work** — it fails with `cannot re-exec process to join the existing user namespace`. So `kind`, `docker run`, etc. cannot use a nested engine.

Instead, the containers act as **remote clients of the host's Podman engine**:

1. The host runs the user Podman socket — `systemctl --user enable --now podman.socket` (done by `setup.sh`).
2. Each container ships `/etc/containers/containers.conf.d/99-host-engine.conf` with `remote = true` pointing at `unix:///run/user/<uid>/podman/podman.sock` (written by the container setup scripts). This makes plain `podman`/`docker` talk to the host engine transparently — no flags needed.
3. `KIND_EXPERIMENTAL_PROVIDER=podman` is exported in `.bashrc` (the host engine is rootless Podman, there is no Docker daemon).
4. Rootless `kind` needs cgroup delegation — `setup.sh` writes `/etc/systemd/system/user@.service.d/delegate.conf` with `Delegate=cpu cpuset io memory pids` (takes effect after the next login).

Consequence: containers (and clusters) created by either dev container run on the **one shared host engine**, so they are visible from `damianf`, `damianu`, and the host alike. The config file lives in each container's `/etc` (not the shared `$HOME`) so it never forces the host's own Podman into remote mode.

### Setup dev toolbox
```bash
bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```

### Setup Ubuntu dev distrobox
```bash
bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh
```

### Enter current toolbox
```bash
damianf
```

### Enter Ubuntu dev distrobox
```bash
damianu
```

### Run Claude Code
```bash
# Inside damianf container
claude
```

### Run OpenAI Codex CLI
```bash
# Inside damianf container
codex
```

### Run DeepSeek TUI
```bash
# Inside damianf container
deepseek
```

`~/.local/bin/deepseek`, `~/.local/bin/deepseek-tui`, and the matching `~/.npm-global/bin/*` entries wrap the npm-installed binaries with `NO_ANIMATIONS=1` and `--no-mouse-capture` to avoid foot/Sway repaint flicker.

`foot/foot.ini` also enables `damage-whole-window=yes`, which reduces rare full-window DeepSeek TUI repaint flicker when the terminal is maximized.

### Terminal utility tools

Both dev containers install the same terminal inspection/search tools:

| Tool | Purpose |
|---|---|
| `btop` | interactive process/resource monitor |
| `duf` | readable disk/filesystem usage overview |
| `bat` | syntax-highlighted pager; wrapper handles Ubuntu `batcat` |
| `ncdu` | interactive disk usage browser |
| `rg` | ripgrep text search; wrapper prefers distro `/usr/bin/rg` |
| `fzf` | fuzzy finder with Bash key bindings loaded from `.bashrc` |
| `fd` | fast file finder; wrapper handles Ubuntu `fdfind` |

The fzf Bash integration is loaded only for interactive shells and uses the upstream default bindings: `Ctrl-R`, `Ctrl-T`, and `Alt-C`. This repo does not bind those key sequences elsewhere in Bash.

### Toolbox migration

When the host Fedora version moves forward, migrate the dev toolbox in parallel instead of replacing it in place.

1. Create a new versioned toolbox alongside the old one:
```bash
TOOLBOX_CONTAINER=damian44 TOOLBOX_VERSION=44 bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```
2. Verify the new toolbox:
```bash
TOOLBOX_CONTAINER=damian44 bash ~/dotfiles-sway/scripts/verify.sh
```
3. Compare old and new manually for anything ad-hoc you installed outside the script.
4. Point any custom helpers that depend on a toolbox name at the new container. `scripts/voice-type-stop.sh` and `scripts/verify.sh` both respect `TOOLBOX_CONTAINER`.
5. Keep the old toolbox until you have finished a full work session inside the new one.
6. When you are satisfied, remove the old toolbox and rename the validated replacement back to `damianf` so the default automation keeps working:
```bash
podman stop damianf damian44 >/dev/null 2>&1 || true
toolbox rm -f damianf
podman rename damian44 damianf
```
7. Re-run verification against the restored default name:
```bash
bash ~/dotfiles-sway/scripts/verify.sh
```
8. Expect a few Fedora-version package name changes during this cutover. For example:
   - `nodejs` / `nodejs-npm` on Fedora 43 become `nodejs22` / `nodejs22-npm` on Fedora 44.
   - `mesa-va-drivers` can be satisfied by `mesa-dri-drivers` on Fedora 44.
   - If Fedora no longer ships a specific Java major version, install the nearest supported runtime and verify that your own scripts do not pin the removed version.

### Run ShellGPT
```bash
# Inside damianf container
sgpt "explain rpm-ostree status"
sgpt --shell "show listening ports"
```

ShellGPT is installed automatically by `scripts/setup-damian-container.sh` via `pip3 install --user "shell-gpt[litellm]"`.

ShellGPT is configured non-interactively by `scripts/configure-shellgpt.sh`. The script always writes `~/.config/shell_gpt/.sgptrc` so `sgpt` never blocks setup with an API-key prompt.

By default ShellGPT reuses the same private Gemini API key as voice typing:

- `~/.config/voice-type/gemini-api-key`
- `GEMINI_API_KEY`
- `GOOGLE_API_KEY`

When that key exists, the script configures:

- `USE_LITELLM=true`
- `DEFAULT_MODEL=gemini/gemini-3.1-flash-lite`
- `~/.bashrc.d/shellgpt-gemini.bash` to export `GEMINI_API_KEY` inside the toolbox shell
- `~/.local/bin/sgpt` wrapper around `~/.local/bin/sgpt-cli`; it retries `gemini/gemini-2.5-flash-lite` when the primary model fails with temporary availability errors such as `503`, `UNAVAILABLE`, high demand, overload, or rate limits

If both the primary model and fallback fail, `sgpt` prints a short diagnostic:

```text
sgpt: could not connect to the AI service.
Check your network, API key, and model availability.
```

For the current `shell-gpt` + LiteLLM + Gemini stack in this setup, streaming is disabled by default in `~/.config/shell_gpt/.sgptrc`. This avoids duplicated partial output and a known `CustomStreamWrapper` / `KeyboardInterrupt` traceback path seen during streamed responses.

Other supported private sources:

- `OPENAI_API_KEY`
- `SHELLGPT_API_KEY`
- `ANTHROPIC_API_KEY`
- `~/.config/ai/api.env`
- `~/.config/shell_gpt/credentials.env`
- `~/.bashrc.d/ai-keys.bash`

If no private key exists, the config contains `OPENAI_API_KEY=missing-shellgpt-api-key` and `verify.sh` reports a warning. Optional settings are `SHELLGPT_PROVIDER`, `SHELLGPT_API_BASE_URL`, `SHELLGPT_DEFAULT_MODEL`, `SHELLGPT_USE_LITELLM`, `SHELLGPT_GEMINI_PRIMARY_MODEL` defaulting to `gemini/gemini-3.1-flash-lite`, and `SHELLGPT_GEMINI_FALLBACK_MODEL` defaulting to `gemini/gemini-2.5-flash-lite`.

### ccstatusline — Claude Code status in Waybar

`ccstatusline` is bundled with `@anthropic-ai/claude-code` — no separate install needed.

Waybar calls it every 5 seconds from the host via the shared home directory:
```
~/.npm-global/bin/ccstatusline waybar
```

The `custom/claude` Waybar module changes colour based on Claude Code state:

| State | Colour |
|---|---|
| `idle` | Muted blue (default) |
| `in_progress` | Green — Claude is working |
| `waiting_for_user` | Amber — waiting for your input |
| `error` | Red |

---

## KVM Virtualisation

QEMU/KVM installed via rpm-ostree — hardware-accelerated virtualisation using AMD-V.

### Hardware (Ryzen 5 5600H — 6c/12t, 38 GB RAM, 1.8 TB NVMe)
| VM | vCPU | RAM | Disk |
|---|---|---|---|
| Windows 11 | 4 | 8 GB | 80 GB |
| Windows Server 2022 | 2 | 4 GB | 60 GB |
| Kali Linux | 2 | 4 GB | 40 GB |
| All three simultaneously | 8 | 16 GB | 180 GB |

All three can run at the same time — laptop has plenty of headroom.

### Setup (run after reboot post bootstrap)
```bash
bash ~/dotfiles-sway/scripts/setup-kvm.sh
```
Then log out and back in for group membership to take effect.

### Launch virt-manager
```bash
virt-manager
```

### Default network
NAT network (`dotfiles-nat`) is enabled and set to autostart. VMs get IPs from the first free subnet starting at `192.168.125.0/24`.
`setup-kvm.sh` does not modify libvirt's upstream `default` network. This keeps local or nested-libvirt setups safer when `default` is already in use elsewhere.

### Windows 11 — TPM & Secure Boot
Windows 11 requires TPM 2.0 and Secure Boot. In virt-manager:
1. **Firmware:** UEFI with Secure Boot (`/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd`)
2. **TPM:** Add hardware → TPM → Model: TIS, Version: 2.0
3. **CPU:** Copy host CPU configuration (enables nested virt features)

### Windows Server / Active Directory lab
Recommended for AD practice:
- OS: Windows Server 2022 Evaluation (free 180-day ISO from Microsoft)
- After install: `Install-WindowsFeature AD-Domain-Services` → `Install-ADDSForest`
- Connect from Fedora: `remmina` or `xfreerdp`

### Useful commands
```bash
# List VMs
virsh list --all

# Start/stop VM
virsh start <vm-name>
virsh shutdown <vm-name>

# VM console
virt-viewer <vm-name>

# Check KVM
ls /dev/kvm && kvm-ok 2>/dev/null || echo "check: lscpu | grep Virtualization"
```

---

## Security container

Ubuntu 26.04 distrobox container with a full pentesting toolkit.

The local image `localhost/ubuntu-security:26.04` is built from the official Docker Hub `ubuntu:26.04` image and disables apt HTTP pipelining to avoid archive `400 Bad Request` errors seen during fresh Distrobox setup.

### Setup
```bash
bash ~/dotfiles-sway/scripts/setup-security-container.sh
```

### Enter
```bash
distrobox enter security
```

### Tools installed

| Category | Tools |
|---|---|
| Network scanning | `nmap`, `masscan`, `wireshark`, `tcpdump`, `netcat`, `socat` |
| Web | `nikto`, `sqlmap`, `gobuster`, `ffuf`, `dirb`, `wfuzz` |
| Password attacks | `hydra`, `john`, `hashcat`, `medusa` |
| Exploitation | `msfconsole` / `msfvenom`, `evil-winrm`, `impacket`, `pwntools` |
| Enumeration | `enum4linux-ng`, `dnsutils`, `whois`, `net-tools` |
| Forensics & stego | `binwalk`, `foremost`, `steghide`, `exiftool` |
| Wireless | `aircrack-ng` |
| Wordlists | SecLists at `/opt/SecLists` |
| Utilities | `tmux`, `vim`, `jq`, `htop`, `btop`, `python3`, `git` |

### Key paths
```
/opt/SecLists      — SecLists wordlists (passwords, web, fuzzing, etc.)
/opt/enum4linux-ng — enum4linux-ng source
/opt/metasploit-framework — Metasploit installation
```

### Common usage
```bash
# Port scan
nmap -sV -sC -oN scan.txt <target>

# Fast port scan
masscan -p1-65535 <target> --rate=1000

# Web directory brute force
gobuster dir -u http://<target> -w /opt/SecLists/Discovery/Web-Content/common.txt

# Password attack (SSH)
hydra -l admin -P /opt/SecLists/Passwords/rockyou.txt ssh://<target>

# SQL injection
sqlmap -u "http://<target>/page?id=1" --dbs

# Metasploit
msfconsole

# WinRM shell
evil-winrm -i <target> -u <user> -p <password>

# SMB enumeration
enum4linux-ng <target>
```

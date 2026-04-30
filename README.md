# dotfiles-sway

Personal dotfiles for Fedora Atomic Sway setup.

## What's included

### Window manager & UI
- Sway window manager config (borders, keybindings, idle/lock, screenshots, touchpad)
- Waybar status bar (bottom, muted dark theme, colour thresholds for CPU/RAM/temp/battery, Claude Code status via ccstatusline)
- Autostart layout: terminal on ws1, Vivaldi on ws2, Obsidian on ws3, Claude/ChatGPT PWA on ws4
- Foot terminal config
- Mako notification daemon (5s auto-dismiss)
- Clipboard history manager (clipman + rofi)
- JetBrainsMono Nerd Font + Font Awesome (terminal + Waybar)
- Black solid wallpaper

### Applications (Flatpak)
- Vivaldi browser
- VSCode — code editor
- Obsidian — notes
- Bitwarden — password manager
- Spotify
- OBS Studio — screen recording
- mpv — video player
- JDownloader — download manager
- Sticky — desktop sticky notes (com.vixalien.sticky)

### PWA shortcuts (Mod+D launcher)
- Claude AI — opens as minimal window without browser UI
- ChatGPT — opens as minimal window without browser UI
- WhatsApp — opens as minimal window without browser UI

### System
- `damian` Fedora 43 toolbox container (Fedora dev environment)
- `security` Ubuntu 26.04 distrobox container — full security/pentesting toolkit
- KVM/QEMU virtualisation — virt-manager, virt-install, Windows 11 / Windows Server capable
- distrobox — for Ubuntu containers
- Screenshot tool (grim + slurp)
- Hardware acceleration (VA-API via mesa/amdgpu)
- Firewall baseline (public zone, SSH + mDNS only)
- Voice typing — push-to-talk (`Mod+T`) with local Whisper AI + Gemini UK English correction
- Neovim — modern text editor, available system-wide
- AI terminal tools in toolbox: Claude Code, OpenAI Codex CLI, ShellGPT (`sgpt`)

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

This file is private, outside git, and is shared with the `damian` toolbox through the home directory. Voice typing uses it directly, and `scripts/configure-shellgpt.sh` uses the same key by default through LiteLLM with `DEFAULT_MODEL=gemini/gemini-2.5-flash-lite`. On a fresh machine it should be restored from your private backup or secret manager before `setup-damian-container.sh` runs.

ShellGPT also accepts `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `SHELLGPT_API_KEY`, `ANTHROPIC_API_KEY`, `~/.config/ai/api.env`, `~/.config/shell_gpt/credentials.env`, and `~/.bashrc.d/ai-keys.bash`. Use `SHELLGPT_PROVIDER=openai`, `gemini`, or `anthropic` only when you need to override the automatic choice.

3. Run bootstrap:
```bash
bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
```

Bootstrap will:
- Clone this repository
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
> If the current machine already uses `192.168.122.0/24` for its upstream network, the script moves libvirt's `default` NAT network to `192.168.125.0/24` to avoid breaking connectivity.

7. Set up the damian dev container (node, npm, gh, Claude Code, Codex CLI, ShellGPT):
```bash
bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```

8. Create the security container:
```bash
bash ~/dotfiles-sway/scripts/setup-security-container.sh
```

9. Run full verification:
```bash
bash ~/dotfiles-sway/scripts/verify.sh
```

10. Optional: validate the fresh-install flow in a disposable Fedora Sway Atomic VM:
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
| 2 | Vivaldi browser |
| 3 | Obsidian |
| 4 | Claude AI PWA + ChatGPT PWA |
| 9 | WhatsApp PWA |

### Key bindings

#### Basics
| Shortcut | Action |
|---|---|
| `Mod+Return` | Open terminal (foot) |
| `Mod+D` | Application launcher (rofi) |
| `Mod+Shift+Q` | Close focused window |
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
| `Mod+-` | Show/cycle scratchpad |

#### Autostart trigger
| Shortcut | Action |
|---|---|
| `Mod+Shift+S` | Re-run autostart script (Vivaldi + Claude PWA + ChatGPT PWA + Obsidian) |

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

**Right:** `claude` · `idle_inhibitor` · `pulseaudio` · `network` · `power-profiles-daemon` · `cpu` · `memory` · `temperature` · `backlight` · `language` · `battery` · `clock` · `tray`

### Alert thresholds

| Module | Warning | Critical |
|---|---|---|
| CPU | 70% | 80% (blinking) |
| Memory | 70% | 80% (blinking) |
| Temperature | 85°C | 95°C (blinking) |
| Battery | 40% | 20% (blinking) |

### Fonts
- **Primary:** JetBrainsMono Nerd Font — monospace, icons in terminal and Waybar
- **Secondary:** Font Awesome 6 Free + Font Awesome 6 Brands — additional icons

Both fonts are installed automatically by `setup.sh`.

---

## Keyboard layout

GB layout with Polish characters via PL variant. No switching needed.

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
- NordVPN: no Flatpak available — install via official NordVPN Linux CLI script when needed
- Security container must be created after first reboot (distrobox installed via packages.sh)
- Rebuild security container manually: `bash ~/dotfiles-sway/scripts/setup-security-container.sh`
- Enter security container: `distrobox enter security`
- Default browser set to Vivaldi via xdg-settings

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
├── applications/            # PWA desktop shortcuts (Claude AI, ChatGPT, WhatsApp)
├── scripts/
│   ├── lib-install.sh                 # Shared helpers: state tracking, run_step()
│   ├── verify.sh                      # Post-install verification — checks all components
│   ├── autostart.sh                   # Sway autostart: Vivaldi, Claude PWA, ChatGPT PWA, Obsidian
│   ├── fix-vivaldi-profiles.sh        # Fix Vivaldi crash/session recovery dialog
│   ├── check-hardware.sh              # Hardware check (GPU, VA-API, audio, ...) — writes state
│   ├── setup-kvm.sh                   # KVM/QEMU setup (libvirtd, groups, network) — writes state
│   ├── setup-damian-container.sh      # Toolbox damian: node, npm, gh, Claude Code, Codex CLI, ShellGPT + plugins — writes state
│   ├── configure-shellgpt.sh          # Non-interactive ShellGPT config from private env/API files
│   ├── setup-security-container.sh   # Distrobox security: pentesting toolkit — writes state
│   ├── voice-type-start.sh           # Voice typing: start recording (Mod+T press)
│   ├── voice-type-stop.sh            # Voice typing: stop recording, transcribe, inject text (Mod+T release)
│   └── voice-transcribe.py          # Whisper AI transcription (runs inside damian toolbox)
├── setup.sh                 # Symlinks, Flatpaks, toolbox, fonts, Claude settings
├── packages.sh              # rpm-ostree system packages
└── bootstrap.sh             # Fresh install entry point
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
Get a free key at: https://aistudio.google.com

**Performance (Ryzen 5 5600H, CPU only):**
- First run after boot: ~15–20 s (Whisper model loads from disk)
- Subsequent runs: ~10–15 s per utterance (+ ~1 s Gemini API for English)

**To increase accuracy (slower):** edit `scripts/voice-transcribe.py` and change `"small"` to `"medium"`.

**Audio file:** recorded to `~/.cache/voice-type/voice-input.wav`, deleted after transcription.

---

## Neovim

Modern text editor — Vim fork with Lua config, built-in LSP, and a large plugin ecosystem. Installed on the host via rpm-ostree so it's available everywhere (terminal, toolbox, scripts).

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

**Config file:** `~/.config/nvim/init.lua` (Lua) — create to customise.

---

## Vivaldi profile recovery

If Vivaldi shows Session Recovery dialog after reboot, the crash flag fix runs automatically on every sway start via `scripts/fix-vivaldi-profiles.sh`.

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
│   └─ User Flatpaks from Flathub: Obsidian, Vivaldi, VSCode, Bitwarden, Spotify, OBS, mpv, JDownloader
│
├─ toolbox: damian (Fedora 43) — dev/DevOps
│   ├─ node 22
│   ├─ npm
│   ├─ git
│   ├─ gh (GitHub CLI)
│   ├─ claude (Claude Code)
│   ├─ codex (OpenAI Codex CLI)
│   ├─ sgpt (ShellGPT terminal assistant)
│   ├─ ccstatusline (Claude Code Waybar integration)
│   └─ faster-whisper (local Whisper AI for voice typing)
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

### Setup damian container
```bash
bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```

### Enter damian container
```bash
toolbox enter damian
```

### Run Claude Code
```bash
# Inside damian container
claude
```

### Run OpenAI Codex CLI
```bash
# Inside damian container
codex
```

### Run ShellGPT
```bash
# Inside damian container
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
- `DEFAULT_MODEL=gemini/gemini-2.5-flash-lite`
- `~/.bashrc.d/shellgpt-gemini.bash` to export `GEMINI_API_KEY` inside the toolbox shell

Other supported private sources:

- `OPENAI_API_KEY`
- `SHELLGPT_API_KEY`
- `ANTHROPIC_API_KEY`
- `~/.config/ai/api.env`
- `~/.config/shell_gpt/credentials.env`
- `~/.bashrc.d/ai-keys.bash`

If no private key exists, the config contains `OPENAI_API_KEY=missing-shellgpt-api-key` and `verify.sh` reports a warning. Optional settings are `SHELLGPT_PROVIDER`, `SHELLGPT_API_BASE_URL`, `SHELLGPT_DEFAULT_MODEL`, and `SHELLGPT_USE_LITELLM`.

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
NAT network (`default`) is enabled and set to autostart. VMs get IPs in `192.168.122.0/24`.
If `192.168.122.0/24` is already present before libvirt starts, `setup-kvm.sh` redefines the `default` network as `192.168.125.0/24`. This matters for nested validation VMs, where the outer host libvirt network commonly already owns `192.168.122.0/24`.

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

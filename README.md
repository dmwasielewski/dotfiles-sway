# dotfiles-sway

Personal dotfiles for Fedora Atomic Sway setup.

## What's included

### Window manager & UI
- Sway window manager config (borders, keybindings, idle/lock, screenshots, touchpad)
- Waybar status bar (bottom, muted dark theme, colour thresholds for CPU/RAM/temp/battery)
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

### PWA shortcuts (Mod+D launcher)
- Claude AI — opens as minimal window without browser UI
- ChatGPT — opens as minimal window without browser UI
- WhatsApp — opens as minimal window without browser UI

### System
- `damian` Fedora 43 toolbox container (Fedora dev environment)
- `security` Ubuntu 24.04 distrobox container — full security/pentesting toolkit
- distrobox — for Ubuntu containers
- Screenshot tool (grim + slurp)
- Hardware acceleration (VA-API via mesa/amdgpu)
- Firewall baseline (public zone, SSH + mDNS only)

---

## Fresh install

### Prerequisites

1. Generate SSH key and add to GitHub:
```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
```

Then add the key at: https://github.com/settings/ssh/new

2. Run bootstrap:
```bash
bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
```

Bootstrap will:
- Clone this repository
- Run setup.sh (symlinks, Flatpaks, toolbox, fonts)
- Run packages.sh (system packages via rpm-ostree)

3. Reboot after bootstrap completes:
```bash
systemctl reboot
```

4. After reboot set up the damian dev container (node, npm, gh, Claude Code):
```bash
bash ~/dotfiles-sway/scripts/setup-damian-container.sh
```

5. Create the security container:
```bash
bash ~/dotfiles-sway/scripts/setup-security-container.sh
```

6. Verify hardware after reboot:
```bash
bash ~/dotfiles-sway/scripts/check-hardware.sh
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
| 600s (10 min) | Screen locks (`swaylock`, black screen) + display off |
| 900s (15 min) | System suspends (`systemctl suspend`) |
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

**Right:** `idle_inhibitor` · `pulseaudio` · `network` · `power-profiles-daemon` · `cpu` · `memory` · `temperature` · `backlight` · `language` · `battery` · `clock` · `tray`

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
├── sway/                    # Sway window manager config
├── waybar/                  # Waybar status bar config + style
├── foot/                    # Foot terminal config
├── mako/                    # Mako notification config
├── applications/            # PWA desktop shortcuts (Claude, ChatGPT, WhatsApp)
├── scripts/
│   ├── autostart.sh                   # Sway autostart: Vivaldi, Claude PWA, ChatGPT PWA, Obsidian
│   ├── fix-vivaldi-profiles.sh        # Fix Vivaldi crash/session recovery dialog
│   ├── setup-damian-container.sh      # Fedora toolbox: node, npm, gh, Claude Code
│   ├── setup-security-container.sh    # Ubuntu distrobox: nmap, wireshark, netcat, htop, btop
│   └── check-hardware.sh             # Hardware verification script
├── setup.sh                 # Symlinks, Flatpaks, toolbox, fonts
├── packages.sh              # rpm-ostree system packages
└── bootstrap.sh             # Fresh install entry point
```

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
│   └─ Obsidian, Vivaldi, VSCode, Bitwarden, Spotify, OBS, mpv, JDownloader
│
├─ toolbox: damian (Fedora 43) — dev/DevOps
│   ├─ node 22
│   ├─ npm
│   ├─ git
│   ├─ gh (GitHub CLI)
│   └─ claude (Claude Code)
│
└─ distrobox: security (Ubuntu 24.04) — pentesting & security research
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

---

## Security container

Ubuntu 24.04 distrobox container with a full pentesting toolkit.

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

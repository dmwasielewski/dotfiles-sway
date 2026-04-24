# CLAUDE.md — AI Instructions for dotfiles-sway

This file is for AI assistants (Claude, Gemini, Copilot, etc.). Read it fully before making any suggestions or changes.

---

## Project goal

Fully automated, reproducible setup of **Fedora Atomic Sway** — from a fresh OS install to a complete working system with all applications, containers, virtual machines, and configuration. Running `bootstrap.sh` should reproduce the exact state of the system without any manual steps beyond SSH key setup.

The system belongs to **Damian** (dmwasielewski). Communicate in **Polish** unless asked otherwise.

---

## Critical environment rules — read before touching anything

### Host OS: Fedora Atomic (immutable)

- The host uses **rpm-ostree**, NOT `dnf`. Never suggest `sudo dnf install` on the host.
- Package changes on the host require a **reboot** to take effect.
- Host is immutable — config files go in `~/.config/`, not `/etc/` unless absolutely necessary.
- Flatpak is the primary app delivery mechanism for GUI apps.

### Claude Code runs inside a Toolbox container

- Claude Code is installed **inside the `damian` toolbox container** (Fedora 43), not on the host.
- Bash commands from Claude Code run **inside the toolbox**, not on the host.
- To run a command **on the host** from inside the toolbox: `flatpak-spawn --host <command>`
- The home directory (`~`) is **shared** between host and toolbox — files written to `~` are visible on both sides.

### KVM / libvirt

- `virsh` and `virt-install` must always use: `--connect qemu:///system`
- `virt-manager` connects to host automatically if run from toolbox via `flatpak-spawn --host`.
- The `libvirtd` socket is on the host — accessible from toolbox because of the shared home and socket forwarding.

---

## Repository structure

```
dotfiles-sway/
├── CLAUDE.md                          ← this file
├── bootstrap.sh                       ← fresh install entry point (SSH key required first)
├── packages.sh                        ← rpm-ostree system packages (host)
├── setup.sh                           ← symlinks, Flatpaks, toolbox creation, fonts
├── user-dirs.dirs                     ← XDG user directories config
├── sway/config                        ← Sway window manager config
├── waybar/config                      ← Waybar status bar config (JSON)
├── waybar/style.css                   ← Waybar CSS theme
├── foot/foot.ini                      ← Foot terminal config
├── mako/config                        ← Mako notification daemon config
├── applications/
│   ├── claude-ai.desktop              ← Claude AI PWA shortcut
│   ├── chatgpt.desktop                ← ChatGPT PWA shortcut
│   └── whatsapp.desktop               ← WhatsApp PWA shortcut
└── scripts/
    ├── autostart.sh                   ← Sway autostart: opens apps on correct workspaces
    ├── fix-vivaldi-profiles.sh        ← Fixes Vivaldi crash/session recovery dialog on start
    ├── check-hardware.sh              ← Verifies VA-API, GPU, KVM after reboot
    ├── setup-kvm.sh                   ← KVM/QEMU setup (libvirtd, user groups, NAT network)
    ├── setup-damian-container.sh      ← Fedora toolbox: node, npm, gh, Claude Code
    └── setup-security-container.sh   ← Ubuntu 24.04 distrobox: full pentesting toolkit
```

---

## Fresh install — full sequence

### Before bootstrap

```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
# Add to https://github.com/settings/ssh/new
```

### Step 1 — Bootstrap

```bash
bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
```

Bootstrap does:
1. Clones this repo to `~/dotfiles-sway`
2. Runs `setup.sh` — symlinks, Flatpaks, toolbox creation, fonts
3. Runs `packages.sh` — installs system packages via rpm-ostree

### Step 2 — Reboot (mandatory after rpm-ostree)

```bash
systemctl reboot
```

### Step 3 — Post-reboot scripts (run in this order)

```bash
bash ~/dotfiles-sway/scripts/check-hardware.sh       # verify GPU/VA-API/KVM
bash ~/dotfiles-sway/scripts/setup-kvm.sh            # enable libvirtd, add user to groups
# Log out and back in for group changes to take effect
bash ~/dotfiles-sway/scripts/setup-damian-container.sh   # dev toolbox
bash ~/dotfiles-sway/scripts/setup-security-container.sh # security distrobox
```

### Step 4 — Manual post-install steps (not automated yet)

- Set `ANTHROPIC_API_KEY` in `~/.bashrc` inside the `damian` container
- Pair Bluetooth devices manually via `bluetoothctl`
- Install NordVPN via official Linux CLI script (no Flatpak available)
- Set up virtual machines — see KVM section below
- Log in to: Vivaldi, Bitwarden, Obsidian, Spotify, GitHub (gh auth login)

---

## System layers — what is installed where

### Layer 1: Host (rpm-ostree LayeredPackages)

Managed by `packages.sh`. Install with `rpm-ostree install`, requires reboot.

| Package | Purpose |
|---|---|
| `mako` | Notification daemon |
| `libva-utils` | VA-API hardware acceleration tools |
| `clipman` | Clipboard history manager |
| `distrobox` | Ubuntu container support |
| `unzip` | Required for font installation |
| `qemu-kvm` | KVM virtualisation engine |
| `libvirt` | Virtualisation management |
| `libvirt-daemon-config-network` | Default NAT network for VMs |
| `virt-manager` | GUI VM manager |
| `virt-viewer` | VM display viewer |
| `virt-install` | CLI VM creation |
| `bridge-utils` | Network bridging for VMs |
| `intel-media-driver` | Intel GPU only (auto-detected) |

AMD GPU: mesa-va-drivers is already in Fedora Atomic base — no extra package needed.

### Layer 2: Flatpak (GUI apps)

Managed by `setup.sh`. Installed from Flathub.

| App | Flatpak ID | Purpose |
|---|---|---|
| Vivaldi | `com.vivaldi.Vivaldi` | Primary browser (default) |
| VSCode | `com.visualstudio.code` | Code editor |
| Obsidian | `md.obsidian.Obsidian` | Notes (ws3) |
| Bitwarden | `com.bitwarden.desktop` | Password manager |
| Spotify | `com.spotify.Client` | Music |
| OBS Studio | `com.obsproject.Studio` | Screen recording |
| mpv | `io.mpv.Mpv` | Video player |
| JDownloader | `org.jdownloader.JDownloader` | Download manager |
| Sticky | `com.vixalien.sticky` | Desktop sticky notes |

Notes:
- `pavucontrol` is in Fedora Atomic base — no separate install needed.
- NordVPN: no Flatpak available — install via official NordVPN Linux CLI when needed.

### Layer 3: toolbox `damian` (Fedora 43 dev environment)

Managed by `scripts/setup-damian-container.sh`. Use `toolbox enter damian` to enter.

| Tool | Purpose |
|---|---|
| `node 22` | Node.js runtime |
| `npm` | Package manager |
| `gh` | GitHub CLI |
| `claude` (`@anthropic-ai/claude-code`) | Claude Code CLI |
| `ccstatusline` | Claude Code Waybar status (bundled with claude-code) |

npm prefix is set to `~/.npm-global` — global npm packages visible from host too.

### Layer 4: distrobox `security` (Ubuntu 24.04 pentesting)

Managed by `scripts/setup-security-container.sh`. Use `distrobox enter security` to enter.

| Category | Tools |
|---|---|
| Network | `nmap`, `masscan`, `wireshark`, `tcpdump`, `netcat`, `socat` |
| Web | `nikto`, `sqlmap`, `gobuster`, `ffuf`, `dirb`, `wfuzz` |
| Passwords | `hydra`, `john`, `hashcat`, `medusa` |
| Exploitation | `metasploit`, `evil-winrm`, `impacket`, `pwntools` |
| Enumeration | `enum4linux-ng`, `dnsutils`, `whois`, `net-tools` |
| Forensics | `binwalk`, `foremost`, `steghide`, `exiftool`, `aircrack-ng` |
| Wordlists | SecLists at `/opt/SecLists` |
| Utilities | `tmux`, `vim`, `jq`, `htop`, `btop`, `curl`, `wget`, `python3`, `git` |

### Layer 5: KVM Virtual Machines

Host hardware: **Ryzen 5 5600H** (6c/12t), **38 GB RAM**, **1.8 TB NVMe**. All three VMs can run simultaneously.

| VM | vCPU | RAM | Disk | Status |
|---|---|---|---|---|
| Windows 11 Pro | 4 | 8 GB | 80 GB qcow2 | Installed |
| Windows Server 2022 | 2 | 4 GB | 60 GB | Planned |
| Kali Linux | 2 | 4 GB | 40 GB | Planned |

**Windows 11 specifics:**
- Requires TPM 2.0 + Secure Boot (OVMF secboot firmware)
- virtio drivers required during install — use `viostor\w11\amd64` (NOT vioscsi)
- Bypass Microsoft account: Shift+F10 → `OOBE\BYPASSNRO`
- After install: run `virtio-win-guest-tools.exe` from the virtio-win ISO
- Shared folder: `~/kvm-shared` via virtiofs (requires WinFSP + VirtioFsSvc in Windows)
- Disk: `/var/lib/libvirt/images/win11.qcow2`

**Virsh commands:**
```bash
virsh --connect qemu:///system list --all
virsh --connect qemu:///system start win11
virsh --connect qemu:///system shutdown win11
virt-viewer --connect qemu:///system win11
```

---

## Sway window manager

### Modifier key
`Super` (Windows key) — `$mod` in config.

### Keyboard layout
GB layout with PL variant. Polish characters via compose key — no layout switching needed.

### Wallpaper
Solid black (`#000000`) — no image.

### Window borders
- Style: `pixel 1` (1px, no title bar)
- Focused: dark amber `#5c3000`
- Floating: no border
- Gaps: none

### Idle / lock / suspend
| Timeout | Action |
|---|---|
| 600s | Display off |
| 900s | Screen lock (swaylock, black) |
| 1200s | System suspend |
| Before sleep | Auto-lock |

### Workspace autostart layout
| Workspace | Content |
|---|---|
| 1 | Foot terminal |
| 2 | Vivaldi browser |
| 3 | Obsidian |
| 4 | Claude AI PWA + ChatGPT PWA |
| 9 | WhatsApp PWA |

`Mod+Shift+S` re-runs the autostart script.

### Key bindings summary
| Shortcut | Action |
|---|---|
| `Mod+Return` | Terminal (foot) |
| `Mod+D` | App launcher (rofi) |
| `Mod+C` | Clipboard history (clipman + rofi) |
| `Mod+Shift+Q` | Close window |
| `Mod+Shift+C` | Reload Sway config |
| `Mod+Shift+E` | Exit Sway |
| `Mod+Shift+Escape` | Lock screen |
| `Print` | Full screenshot → `~/Pictures/` |
| `Mod+Print` | Region screenshot (slurp) |
| `Mod+H/J/K/L` | Focus (Vim-style) |
| `Mod+Shift+H/J/K/L` | Move window |
| `Mod+1–9` | Switch workspace |
| `Mod+Shift+1–9` | Move window to workspace |
| `Mod+F` | Fullscreen |
| `Mod+Shift+Space` | Toggle floating |
| `Mod+R` | Resize mode |
| `Mod+Shift+-` / `Mod+-` | Scratchpad send / show |

---

## Waybar

- Position: **bottom**, height 25px
- Dark muted blue-slate theme (low contrast, easy on the eyes)
- Modules right → left: `claude` status · idle inhibitor · audio · network · power profile · CPU · RAM · temp · backlight · language · battery · clock · tray
- `custom/claude`: calls `~/.npm-global/bin/ccstatusline waybar` every 5s — shows Claude Code state (idle/working/waiting/error) with colour coding

**Alert thresholds:**
| Module | Warning | Critical |
|---|---|---|
| CPU | 70% | 80% |
| RAM | 70% | 80% |
| Temperature | 85°C | 95°C |
| Battery | 40% | 20% |

---

## Fonts

- **JetBrainsMono Nerd Font** — terminal + Waybar icons
- **Font Awesome 6 Free + Brands** — additional Waybar icons

Both installed to `~/.local/share/fonts/` by `setup.sh`.

---

## PWA shortcuts (applications/)

Three `.desktop` files that open web apps as minimal Vivaldi windows (no browser UI):
- Claude AI → `claude.ai`
- ChatGPT → `chatgpt.com`
- WhatsApp → `web.whatsapp.com`

Symlinked to `~/.local/share/applications/` by `setup.sh`.

---

## Known issues and workarounds

| Issue | Fix |
|---|---|
| Vivaldi shows Session Recovery dialog on start | `fix-vivaldi-profiles.sh` runs automatically on every Sway start |
| Vivaldi crash flag stuck | `pkill -f vivaldi; sleep 2; bash ~/dotfiles-sway/scripts/fix-vivaldi-profiles.sh` |
| virtiofs not working in Windows 11 | Check VirtioFsSvc service is running in Windows; requires WinFSP |
| Security container missing after OS reinstall | Run `setup-security-container.sh` — distrobox must be installed first (packages.sh + reboot) |
| Bluetooth GUI applet has connection issues | Use `bluetoothctl` CLI instead |

---

## AI workflow rules

These rules apply whenever an AI assists with this project:

1. **Never use `dnf` on the host.** Host is immutable. Use `rpm-ostree install` + reboot.
2. **Never use `apt` or `dnf` directly from toolbox for host changes.** Use `flatpak-spawn --host rpm-ostree install ...`.
3. **Always use `--connect qemu:///system`** with virsh/virt-install.
4. **When the user installs or changes anything system-related**, update the relevant file:
   - New rpm-ostree package → `packages.sh`
   - New Flatpak → `setup.sh`
   - New config file → copy/symlink it into the repo + add symlink to `setup.sh`
   - New script → add to `scripts/`, make executable, document in README
   - Any change → commit + push to GitHub
5. **Config files are symlinked, not copied** — the repo is the source of truth. Edit files in `~/dotfiles-sway/`, not in `~/.config/` directly.
6. **Goal is zero manual steps** after `bootstrap.sh` + reboot + 4 post-reboot scripts. If something requires a manual step, automate it or document it clearly in README under "Manual post-install steps".
7. **Keep README.md and CLAUDE.md in sync** when adding new apps, packages, VMs, or scripts.
8. **Communicate in Polish** with the user.

---

## What is complete

- [x] Sway config (borders, keybindings, idle/lock, touchpad, autostart)
- [x] Waybar (dark theme, CPU/RAM/temp/battery thresholds, Claude Code status)
- [x] Foot terminal config
- [x] Mako notifications (5s auto-dismiss)
- [x] Clipboard manager (clipman + rofi)
- [x] Fonts (JetBrainsMono Nerd Font, Font Awesome)
- [x] All Flatpak apps installed via setup.sh
- [x] All system packages via packages.sh (rpm-ostree)
- [x] PWA shortcuts (Claude, ChatGPT, WhatsApp)
- [x] toolbox `damian` with node, npm, gh, Claude Code
- [x] distrobox `security` with full pentesting toolkit
- [x] KVM/QEMU setup script
- [x] Windows 11 Pro VM installed and running
- [x] Hardware check script (VA-API, GPU, KVM)
- [x] Vivaldi profile crash fix (auto on Sway start)
- [x] Firewall baseline (public zone, SSH + mDNS only)
- [x] bootstrap.sh — single entry point for fresh install

## What is planned / in progress

- [ ] Windows Server 2022 VM — Active Directory lab (Sysadmin AD Lab project)
- [ ] Kali Linux VM
- [ ] virtiofs fully working in Windows 11 (VirtioFsSvc setup)
- [ ] NordVPN — automate install in bootstrap (currently manual CLI script)
- [ ] ANTHROPIC_API_KEY setup automation in damian container
- [ ] `gh auth login` automation
- [ ] Active Directory lab: Domain Controller, joined workstations, GPO, users

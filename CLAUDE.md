# CLAUDE.md — AI Instructions for dotfiles-sway

This file is for AI assistants (Claude, Gemini, Copilot, etc.). Read it fully before making any suggestions or changes.

---

## Project goal

Fully automated, reproducible setup of **Fedora Atomic Sway** — from a fresh OS install to a complete working system with all applications, containers, virtual machines, and configuration. Running `bootstrap.sh` should reproduce the exact state of the system without any manual steps beyond network access to GitHub and the separate login steps listed below.

The system belongs to **Damian** (dmwasielewski). Communicate in **Polish** unless asked otherwise.

---

## Critical environment rules — read before touching anything

### Host OS: Fedora Atomic (immutable)

- The host uses **rpm-ostree**, NOT `dnf`. Never suggest `sudo dnf install` on the host.
- Package changes on the host require a **reboot** to take effect.
- Host is immutable — config files go in `~/.config/`, not `/etc/` unless absolutely necessary.
- Flatpak is the primary app delivery mechanism for GUI apps.

### AI coding CLIs run inside a Toolbox container

- Claude Code, OpenAI Codex CLI, DeepSeek TUI, and ShellGPT are installed **inside the dev toolbox container** (`damian` by default), not as host rpm-ostree packages.
- Bash commands from these CLIs run **inside the toolbox**, not on the host.
- To run a command **on the host** from inside the toolbox: `flatpak-spawn --host <command>`
- The home directory (`~`) is **shared** between host and toolbox — files written to `~` are visible on both sides.

### Install diagnostics

- Every install script writes step state to `~/.dotfiles-install-state`.
- Every install script appends full terminal output to `~/.dotfiles-install.log`.
- Each log line is timestamped as `[YYYY-MM-DD HH:MM:SS] ...`.
- When debugging a failed fresh install, check in this order:
  1. `cat ~/.dotfiles-install-state`
  2. `tail -200 ~/.dotfiles-install.log`
  3. `bash ~/dotfiles-sway/scripts/verify.sh`
- If adding a new automated install step, update the state tracking, logging-aware script flow, `verify.sh`, and user-facing documentation.

### KVM / libvirt

- `virsh` and `virt-install` must always use: `--connect qemu:///system`
- `virt-manager` connects to host automatically if run from toolbox via `flatpak-spawn --host`.
- The `libvirtd` socket is on the host — accessible from toolbox because of the shared home and socket forwarding.

---

## Repository structure

```
dotfiles-sway/
├── CLAUDE.md                          ← this file
├── bootstrap.sh                       ← fresh install entry point (HTTPS clone by default)
├── packages.sh                        ← rpm-ostree system packages (host)
├── setup.sh                           ← symlinks, Flatpaks, toolbox creation, fonts
├── user-dirs.dirs                     ← XDG user directories config
├── nvim/
│   └── christitustech                 ← git submodule: ChrisTitusTech/neovim (`titus-kickstart` config)
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
    ├── lib-install.sh                 ← Shared helpers: state tracking, run_step()
    ├── verify.sh                      ← Full post-install verification — checks every component
    ├── autostart.sh                   ← Sway autostart: opens apps on correct workspaces
    ├── fix-vivaldi-profiles.sh        ← Fixes Vivaldi crash/session recovery dialog on start
    ├── check-hardware.sh              ← Verifies VA-API, GPU, KVM after reboot — writes state
    ├── setup-kvm.sh                   ← KVM/QEMU setup (libvirtd, user groups, NAT network) — writes state
    ├── setup-neovim-config.sh         ← Neovim 0.12.1 user-local binary + Chris Titus Tech config symlink
    ├── setup-nordvpn.sh               ← NordVPN CLI install + nordvpnd enable/start + group setup — writes state
    ├── setup-adguard.sh               ← AdGuard for Linux CLI install — writes state
    ├── setup-damian-container.sh      ← Toolbox damian: node, npm, gh, Claude Code, Codex CLI, ShellGPT + plugins — writes state
    ├── configure-shellgpt.sh          ← Non-interactive ShellGPT config from private env/API files
    ├── adguard-waybar.sh              ← AdGuard Waybar status helper (AG + click toggle)
    ├── nordvpn-waybar.sh              ← NordVPN Waybar status helper (VPN + click toggle)
    ├── power-menu.sh                  ← Rofi power menu (shutdown/reboot/suspend/hibernate/logout)
    ├── setup-security-container.sh   ← Distrobox security: pentesting toolkit — writes state
    ├── voice-type-start.sh           ← Voice typing: start recording on Mod+T press
    ├── voice-type-stop.sh            ← Voice typing: stop, transcribe, inject text on Mod+T release
    └── voice-transcribe.py          ← Whisper AI transcription (runs inside damian toolbox)
```

Runtime diagnostic files:

```
~/.dotfiles-install-state              ← latest status for each install phase
~/.dotfiles-install.log                ← timestamped output from bootstrap/setup scripts
```

---

## Fresh install — full sequence

### Before bootstrap

```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
```

An SSH key is only needed if you want to use SSH remotes or private forks. `bootstrap.sh` clones this repo over HTTPS by default.

If ShellGPT should be ready immediately after the dev toolbox setup, restore `~/.config/voice-type/gemini-api-key` before `setup-damian-container.sh` runs. ShellGPT reuses that same Gemini key through LiteLLM by default. ShellGPT prefers `gemini-3.1-flash-lite-preview` and the installed `sgpt` wrapper retries `gemini-2.5-flash` when the preview model is overloaded. Other supported private sources are `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `SHELLGPT_API_KEY`, `ANTHROPIC_API_KEY`, `~/.config/ai/api.env`, `~/.config/shell_gpt/credentials.env`, and `~/.bashrc.d/ai-keys.bash`. These files are private and must not be committed to this repo.

### Step 1 — Bootstrap

```bash
bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
```

Bootstrap does:
1. Clones this repo to `~/dotfiles-sway`
2. Initialises git submodules, including `ChrisTitusTech/neovim`
3. Runs `setup.sh` — symlinks, Flatpaks, toolbox creation, fonts, Neovim user-local binary/config
4. Runs `packages.sh` — installs system packages via rpm-ostree

For a disposable end-to-end validation VM:

```bash
bash ~/dotfiles-sway/scripts/create-fedora-sway-vm.sh
```

That script provisions Fedora Sway Atomic in KVM using the official Fedora Everything installer ISO, injects the host SSH public key into the guest, and runs the Phase 1 bootstrap inside the VM. Fedora live media are not used for this path because Kickstart does not support live images as an installation source.

VM validation details:
- The installer ISO checksum is verified before use.
- Kickstart is injected into the installer initrd with `virt-install --initrd-inject`.
- The Fedora ostree content URL is resolved from `https://ostree.fedoraproject.org/mirrorlist`.
- The disposable VM kickstart uses `ostreesetup --nogpg` because the Fedora 44 netinst Anaconda environment can miss the current ostree signing key even when the installer ISO checksum is valid.
- Anaconda may shut off the VM after installation; the script starts it again from disk and then waits for SSH.
- `setup-kvm.sh` defines a dedicated libvirt NAT network named `dotfiles-nat` on the first free subnet from `192.168.125.0/24` upward; it does not modify libvirt's upstream `default` network.

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

- Set `ANTHROPIC_API_KEY` in private `~/.bashrc.d/ai-keys.bash`
- Pair Bluetooth devices manually via `bluetoothctl`
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
| `wtype` | Wayland keyboard injection (voice typing) |
| `alsa-utils` | `arecord` audio recording (voice typing) |
| `gitleaks` | Secret scanner, enforced by repo `pre-push` hook |
| `ripgrep` | Neovim search dependency |
| `fd-find` | Neovim file finder dependency |
| `fzf` | Neovim fuzzy finder dependency |
| `wl-clipboard` | Neovim Wayland clipboard integration |
| `python3-virtualenv` | Neovim Python tooling dependency |
| `ShellCheck` | Neovim shell linting dependency |
| `libwebp-tools` | Neovim Markdown image paste conversion (`cwebp`) |
| `nodejs` | Neovim Node-based tooling |
| `npm` | Neovim Node package tooling |
| `make` | Neovim build/tooling dependency |

AMD GPU: mesa-va-drivers is already in Fedora Atomic base — no extra package needed.

### Layer 2: Flatpak (GUI apps)

Managed by `setup.sh`. Installed from Flathub as user Flatpaks (`--user`) to avoid host polkit prompts during unattended setup.

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
- Thunderbird is installed as the verified Flathub Flatpak `org.mozilla.Thunderbird`.
- LibreOffice is installed as the verified Flathub Flatpak `org.libreoffice.LibreOffice` (Writer, Calc, Impress).
- NordVPN: official Linux CLI install via `bash ~/dotfiles-sway/scripts/setup-nordvpn.sh` with automatic `nordvpnd` enable/start.
- AdGuard for Linux: official CLI install via `bash ~/dotfiles-sway/scripts/setup-adguard.sh`; first-time activation/configuration remains manual.

### Layer 3: toolbox `damian` (Fedora dev environment, versioned with the host unless overridden)

Managed by `scripts/setup-damian-container.sh`. By default it targets the host Fedora release and the toolbox name `damian`. Override with `TOOLBOX_VERSION=<ver>` and `TOOLBOX_CONTAINER=<name>` for side-by-side migrations.

For toolbox cutovers across Fedora releases, use a parallel container first, verify it, then replace the old default name only at the end:
1. `TOOLBOX_CONTAINER=damian44 TOOLBOX_VERSION=44 bash ~/dotfiles-sway/scripts/setup-damian-container.sh`
2. `TOOLBOX_CONTAINER=damian44 bash ~/dotfiles-sway/scripts/verify.sh`
3. compare old and new for anything ad-hoc outside this repo
4. `podman stop damian damian44 >/dev/null 2>&1 || true && toolbox rm -f damian && podman rename damian44 damian`
5. `bash ~/dotfiles-sway/scripts/verify.sh`

Normal version drift is expected during those migrations. Fedora 44, for example, uses `nodejs22` / `nodejs22-npm` instead of the older generic package names, and `mesa-dri-drivers` satisfies the old `mesa-va-drivers` capability.

| Tool | Purpose |
|---|---|
| `node 22` | Node.js runtime |
| `npm` | Package manager |
| `gh` | GitHub CLI |
| `claude` (`@anthropic-ai/claude-code`) | Claude Code CLI |
| `codex` (`@openai/codex`) | OpenAI Codex CLI |
| `deepseek` (`deepseek-tui`) | DeepSeek TUI |
| `sgpt` (`shell-gpt`) | ShellGPT terminal assistant |
| `ccstatusline` | Claude Code Waybar status (bundled with claude-code) |
| `faster-whisper` | Local Whisper AI speech recognition (voice typing) |
| `markdownlint-cli2` | Markdown linting used by Chris Titus Tech's Neovim config |

npm prefix is set to `~/.npm-global` — global npm packages visible from host too.

ShellGPT config is generated non-interactively by `scripts/configure-shellgpt.sh` into `~/.config/shell_gpt/.sgptrc`. The preferred provider is Gemini via LiteLLM, using the same private key file as voice typing: `~/.config/voice-type/gemini-api-key`. It sets `gemini/gemini-3.1-flash-lite-preview` as the primary ShellGPT model and installs `~/.local/bin/sgpt` as an executable wrapper around `~/.local/bin/sgpt-cli`; the wrapper retries `gemini/gemini-2.5-flash` on temporary availability errors and prints a clear diagnostic if both models fail. If Damian already has a custom unmanaged `sgpt`, the script leaves it untouched instead of overwriting it. If no private API key source exists, the config uses the placeholder `OPENAI_API_KEY=missing-shellgpt-api-key` so `sgpt` never blocks setup with an interactive prompt. Do not commit API keys to this repo.

### Layer 4: distrobox `security` (Ubuntu 26.04 pentesting)

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
| 1200s | Screen lock (swaylock, black) |
| 1800s | System suspend |
| Before sleep | Auto-lock |

Config is in `sway/config.d/90-swayidle.conf` (overrides Fedora's system default `/usr/share/sway/config.d/90-swayidle.conf` added in F44).

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
| `Mod+T` (hold) | Voice typing — hold to record, release to transcribe and type |
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
- Modules right → left: `power` · `nordvpn` · tray · clock · battery · `adguard` · backlight · temp · RAM · CPU · power profile · network · audio · idle inhibitor · `claude` status
- `custom/adguard`: calls `~/.local/bin/adguard-waybar` every 10s — shows `AG`; click toggles protection on/off
- `custom/claude`: calls `~/.npm-global/bin/ccstatusline waybar` every 5s — shows Claude Code state (idle/working/waiting/error) with colour coding
- `custom/nordvpn`: calls `~/.local/bin/nordvpn-waybar` every 15s — shows `VPN`; click toggles connect/disconnect
- `custom/power`: shows ⏻ icon; click opens rofi power menu (shutdown/reboot/suspend/hibernate/logout)

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

## Neovim

Neovim is installed in two layers:

- Fedora `neovim` rpm remains layered as a fallback.
- `scripts/setup-neovim-config.sh` installs the official upstream Neovim `v0.12.1` binary to a versioned directory under `~/.local/opt/`, points `~/.local/opt/nvim-linux-x86_64` and `~/.local/bin/nvim` at the active release, and syncs plugins to Chris Titus Tech's `nvim-pack-lock.json`.

The active config is Chris Titus Tech's `titus-kickstart`, pinned as a git submodule at `nvim/christitustech`:

```bash
~/.config/nvim -> ~/dotfiles-sway/nvim/christitustech/titus-kickstart
```

Do not run Chris's `lin-depend.sh` on the Fedora Atomic host because it uses mutable-distro package managers such as `dnf` directly. Instead, keep its dependency list represented in this repo:

- host dependencies in `packages.sh`
- symlink, upstream Neovim binary, and plugin lockfile sync in `scripts/setup-neovim-config.sh`
- `markdownlint-cli2` in `scripts/setup-damian-container.sh` via the shared `~/.npm-global` prefix
- checks in `scripts/verify.sh`

Known caveat: Chris's config includes WakaTime and an `img-clip.nvim` default path under `/home/titus/...`. Keep this documented; patch only if Damian asks to customise the upstream config.

Do not add `golang` or `luarocks` to the host layer just because Chris's `lin-depend.sh` lists them. On 2026-05-05 they caused `rpm-ostree` depsolve failures by pulling `gcc/glibc-devel` versions that did not match the active Fedora Atomic deployment. Add language-specific tooling later in toolbox or after a deployment update if Damian actually needs it.

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
6. **Before pushing**, run or rely on the configured `.githooks/pre-push` hook. It executes `gitleaks detect --source . --redact --verbose` and must block pushes that contain secrets.
7. **Goal is zero manual steps** after `bootstrap.sh` + reboot + 4 post-reboot scripts. If something requires a manual step, automate it or document it clearly in README under "Manual post-install steps".
8. **Keep README.md and CLAUDE.md in sync** when adding new apps, packages, VMs, or scripts.
9. **Communicate in Polish** with the user.

---

## Claude Code configuration

Claude Code is installed inside the `damian` toolbox container. Its configuration is stored in `~/.claude/` which is shared with the host.

### settings.json

Location: `~/.claude/settings.json` — symlinked from `dotfiles-sway/claude/settings.json` by `setup.sh`.

```json
{
  "statusLine": {
    "type": "command",
    "command": "ccstatusline",
    "padding": 0
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "context7@claude-plugins-official": true
  }
}
```

- `ccstatusline` — displays Claude Code state in Waybar (idle/working/waiting/error)
- Plugins are enabled globally for all projects

### Plugins installed

All three plugins are installed automatically by `setup-damian-container.sh`:

| Plugin ID | Version | Purpose |
|---|---|---|
| `superpowers@claude-plugins-official` | 5.0.7 | Skills system — brainstorming, debugging, TDD, code review, plans, git worktrees, etc. |
| `code-simplifier@claude-plugins-official` | 1.0.0 | Code review and simplification skill |
| `context7@claude-plugins-official` | latest | Fetches live library/framework documentation on demand |

Plugins are installed from the official marketplace: `anthropics/claude-plugins-official` on GitHub.

Install command (run inside the `damian` container):
```bash
claude plugin install superpowers@claude-plugins-official --yes
claude plugin install code-simplifier@claude-plugins-official --yes
claude plugin install context7@claude-plugins-official --yes
```

### MCP servers (cloud — require OAuth login)

These connect via the Claude.ai account and **cannot be automated** — they require browser-based OAuth login on first use. They work automatically after login is done once.

| MCP | Purpose |
|---|---|
| Gmail | Read/send email, manage labels |
| Google Calendar | List/create/update events |
| Google Drive | Read/create files |
| Slack | Read channels, send messages (requires re-auth) |
| context7 | Library docs (via plugin — no auth needed) |
| sequential-thinking | Structured reasoning tool |

To connect MCPs: open `claude.ai` → Settings → Integrations → connect each service.

### OpenAI Codex CLI

Codex CLI is installed automatically by `scripts/setup-damian-container.sh` via npm as `@openai/codex`.

Run it inside the `damian` toolbox:
```bash
toolbox enter damian
codex
```

First use requires interactive login:
```bash
codex login
```

### DeepSeek TUI

DeepSeek TUI is launched through wrapper entries in `~/.local/bin` and `~/.npm-global/bin`. The wrapper calls the npm package entry point directly, sets `NO_ANIMATIONS=1`, and passes `--no-mouse-capture` to reduce foot/Sway repaint flicker.

`foot/foot.ini` also sets `damage-whole-window=yes` to reduce rare full-window DeepSeek TUI repaint flicker when the terminal is maximized.

### ShellGPT

ShellGPT is installed automatically by `scripts/setup-damian-container.sh` via `pip3 install --user "shell-gpt[litellm]"`.

Run it inside the `damian` toolbox:
```bash
toolbox enter damian
sgpt "summarise rpm-ostree status"
sgpt --shell "find large files in the current directory"
```

ShellGPT is configured non-interactively by `scripts/configure-shellgpt.sh`. The script always writes `~/.config/shell_gpt/.sgptrc` so `sgpt` never blocks setup with an API-key prompt.

Preferred source, shared with voice typing:

- `~/.config/voice-type/gemini-api-key`
- `GEMINI_API_KEY`
- `GOOGLE_API_KEY`

With that key, the generated config uses `USE_LITELLM=true` and `DEFAULT_MODEL=gemini/gemini-3.1-flash-lite-preview`, writes `~/.bashrc.d/shellgpt-gemini.bash` to export `GEMINI_API_KEY` in toolbox shells, and installs `~/.local/bin/sgpt` as a fallback wrapper. The original ShellGPT launcher is preserved as `~/.local/bin/sgpt-cli` when the existing launcher is already repo-managed; if Damian already has a custom unmanaged `sgpt`, the script leaves it untouched and prints a warning instead of overwriting it. The wrapper retries `gemini/gemini-2.5-flash` if the preview model fails with temporary availability errors such as `503`, `UNAVAILABLE`, high demand, overload, or rate limits. If both models fail, it prints a short "nie udalo sie polaczyc z AI" diagnostic.

Other supported private sources:

- `OPENAI_API_KEY`
- `SHELLGPT_API_KEY`
- `ANTHROPIC_API_KEY`
- `~/.config/ai/api.env`
- `~/.config/shell_gpt/credentials.env`
- `~/.bashrc.d/ai-keys.bash`

Optional ShellGPT settings:

- `SHELLGPT_PROVIDER` — `auto`, `gemini`, `openai`, or `anthropic`
- `SHELLGPT_API_BASE_URL` or `API_BASE_URL` — defaults to `default`
- `SHELLGPT_DEFAULT_MODEL` or `DEFAULT_MODEL` — defaults to Gemini 3.1 Flash Lite Preview when the voice key exists, otherwise `gpt-4o`
- `SHELLGPT_USE_LITELLM` or `USE_LITELLM` — defaults to `true` for Gemini/Anthropic, otherwise `false`
- `SHELLGPT_GEMINI_PRIMARY_MODEL` and `SHELLGPT_GEMINI_FALLBACK_MODEL` — default to `gemini/gemini-3.1-flash-lite-preview` and `gemini/gemini-2.5-flash`

If no private key exists, the config contains `OPENAI_API_KEY=missing-shellgpt-api-key` and `verify.sh` reports a warning. Do not store ShellGPT API keys in this repo. The home directory is shared with the toolbox, so private files under `~/.config/` are visible where `sgpt` runs.

### Post-install login steps for AI coding CLIs

ShellGPT API configuration is automated by `scripts/configure-shellgpt.sh` from private secret sources. The following login steps still require browser or service interaction after first boot:

1. **Claude API key** — add to private `~/.bashrc.d/ai-keys.bash`:
   ```bash
   mkdir -p ~/.bashrc.d
   chmod 700 ~/.bashrc.d
   echo 'export ANTHROPIC_API_KEY="your-key-here"' > ~/.bashrc.d/ai-keys.bash
   chmod 600 ~/.bashrc.d/ai-keys.bash
   ```
   Get key at: `https://console.anthropic.com/settings/keys`

2. **Claude login** (OAuth):
   ```bash
   toolbox enter damian
   claude login
   ```

3. **Codex login**:
   ```bash
   toolbox enter damian
   codex login
   ```

4. **MCP integrations** — log in to each at `claude.ai` → Settings → Integrations

---

## ChatGPT

ChatGPT is used as a PWA (web app without browser UI) alongside Claude Code. Terminal access to OpenAI Codex is provided by the `codex` CLI in the `damian` toolbox.

- **Shortcut:** `applications/chatgpt.desktop` — symlinked to `~/.local/share/applications/`
- **Autostart:** opens on workspace 4 alongside Claude AI PWA
- **Launcher:** accessible via `Mod+D` (rofi) as "ChatGPT"
- **No installation needed** — it's a web PWA opened in Vivaldi

---

## What is complete

- [x] Sway config (borders, keybindings, idle/lock, touchpad, autostart)
- [x] Waybar (dark theme, CPU/RAM/temp/battery thresholds, Claude Code status, NordVPN/AdGuard toggles, power menu)
- [x] Foot terminal config
- [x] Mako notifications (5s auto-dismiss)
- [x] Clipboard manager (clipman + rofi)
- [x] Fonts (JetBrainsMono Nerd Font, Font Awesome)
- [x] All Flatpak apps installed via setup.sh (Vivaldi, mpv, VSCode, Obsidian, Bitwarden, Thunderbird, LibreOffice, Spotify, OBS, JDownloader, Sticky)
- [x] All system packages via packages.sh (rpm-ostree)
- [x] Neovim 0.12.1 user-local binary with Chris Titus Tech `titus-kickstart` config
- [x] PWA shortcuts (Claude AI, ChatGPT, WhatsApp)
- [x] toolbox `damian` with node, npm, gh, Claude Code, OpenAI Codex CLI, DeepSeek TUI, ShellGPT
- [x] Claude Code settings.json symlinked from dotfiles
- [x] Claude Code plugins auto-installed (superpowers, code-simplifier, context7)
- [x] distrobox `security` with full pentesting toolkit
- [x] KVM/QEMU setup script
- [x] Windows 11 Pro VM installed and running
- [x] Hardware check script (VA-API, GPU, KVM)
- [x] Vivaldi profile crash fix (auto on Sway start)
- [x] Firewall baseline (public zone, SSH + mDNS only)
- [x] Gitleaks installed as a required host package with repo pre-push secret scanning
- [x] bootstrap.sh — single entry point for fresh install, with step-by-step error tracking
- [x] verify.sh — full post-install verification with checklist, failure summary, and fix commands
- [x] lib-install.sh — shared state tracking (`~/.dotfiles-install-state`) used by all scripts
- [x] All install scripts write state — on error, shows exactly what failed and how to resume
- [x] NordVPN — CLI install, `nordvpnd` enable/start, and Waybar toggle helper
- [x] AdGuard for Linux — CLI install, and Waybar toggle helper
- [x] Power button — rofi power menu (shutdown/reboot/suspend/hibernate/logout)
- [x] Voice typing — push-to-talk `Mod+T` with local Whisper AI (faster-whisper, no cloud)

## What is planned / in progress

- [ ] Windows Server 2022 VM — Active Directory lab (Sysadmin AD Lab project)
- [ ] Kali Linux VM
- [ ] virtiofs fully working in Windows 11 (VirtioFsSvc setup)
- [ ] `gh auth login` automation
- [ ] Full idempotency audit across setup.sh, packages.sh, and post-reboot scripts — each step should detect pre-existing resources and continue cleanly

## Manual post-install steps (cannot be automated)

These require human interaction — document them so nothing is forgotten after a fresh install:

| Step | Command / Where |
|---|---|
| Set ANTHROPIC_API_KEY | `~/.bashrc.d/ai-keys.bash` with `export ANTHROPIC_API_KEY="key"` |
| Claude login (OAuth) | `toolbox enter damian` → `claude login` |
| Codex login | `toolbox enter damian` → `codex login` |
| GitHub CLI login | `toolbox enter damian` → `gh auth login` |
| MCP integrations (Gmail, Calendar, Drive, Slack) | `claude.ai` → Settings → Integrations |
| Bluetooth pairing | `bluetoothctl` → `power on` → `scan on` → `pair <MAC>` |
| NordVPN login | `nordvpn login` or, if browser callback fails, `nordvpn login --token <token>` |
| AdGuard first-time setup | `adguard-cli activate` → `adguard-cli configure` → `adguard-cli start` |
| Thunderbird account setup | In-app after Flatpak install |
| Bitwarden / Obsidian / Spotify login | In-app after Flatpak install |
| Vivaldi: sign in, restore bookmarks/extensions | In-app after Flatpak install |

NordVPN notes:
- `scripts/setup-nordvpn.sh` installs the CLI, enables `nordvpnd`, and symlinks the Waybar toggle helper.
- Login cannot be automated. On this setup, browser callback can fail with Flatpak browsers, so token login is the most reliable fallback.
- Generate the token in Nord Account → NordVPN → Advanced settings → Get access token.
- Preferred baseline after login: `Technology: NORDLYNX`, `Firewall: enabled`, `Routing: enabled`, `Notify: enabled`, `Auto-connect: disabled`, `Kill Switch: disabled`.
- Daily manual CLI usage: `nordvpn connect`, `nordvpn status`, `nordvpn disconnect`. Optional country selection: `nordvpn connect Poland`.
- `scripts/setup-adguard.sh` installs the official AdGuard CLI, but activation/configuration remains manual because it requires the interactive first-run wizard and license/trial choice.
- Daily AdGuard CLI usage: `adguard-cli status`, `adguard-cli start`, `adguard-cli stop`. The Waybar `AG` icon also toggles protection on click.
- `scripts/adguard-waybar.sh` is symlinked to `~/.local/bin/adguard-waybar` and shows `AG` on the Waybar (colour indicates state: green enabled, red disabled, amber needs-setup).

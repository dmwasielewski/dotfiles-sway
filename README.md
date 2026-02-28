# dotfiles-sway

Personal dotfiles for Fedora Atomic Sway setup.

## What's included

### Window manager & UI
- Sway window manager config (borders, keybindings, idle/lock, screenshots, touchpad)
- Waybar status bar (bottom, muted dark theme, colour thresholds for CPU/RAM/temp/battery)
- Autostart layout: terminals on ws1, Claude/ChatGPT on ws2, Obsidian on ws3, Vivaldi on ws4
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
- `security` Ubuntu 24.04 distrobox container (nmap, wireshark, netcat, htop, btop)
- distrobox — for Ubuntu containers
- Screenshot tool (grim + slurp)
- Hardware acceleration (VA-API via mesa/amdgpu)
- Firewall baseline (public zone, SSH + mDNS only)

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

4. After reboot create the security container:
```bash
bash ~/dotfiles-sway/scripts/setup-security-container.sh
```

5. Verify hardware after reboot:
```bash
bash ~/dotfiles-sway/scripts/check-hardware.sh
```

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

## Structure
```
dotfiles-sway/
├── sway/                    # Sway window manager config
├── waybar/                  # Waybar status bar config + style
├── foot/                    # Foot terminal config
├── mako/                    # Mako notification config
├── applications/            # PWA desktop shortcuts (Claude, ChatGPT, WhatsApp)
├── scripts/
│   ├── check-hardware.sh              # Hardware verification script
│   └── setup-security-container.sh   # Ubuntu security container setup
├── setup.sh                 # Symlinks, Flatpaks, toolbox, fonts
├── packages.sh              # rpm-ostree system packages
└── bootstrap.sh             # Fresh install entry point
```

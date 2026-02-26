# dotfiles-sway

Personal dotfiles for Fedora Atomic Sway setup.

## What's included

- Sway window manager config (borders, keybindings, idle/lock, screenshots)
- Waybar status bar config (bottom position, default Fedora layout)
- Foot terminal config
- Mako notification daemon (5s auto-dismiss)
- Clipboard history manager (clipman + rofi)
- XDG user directories
- Vivaldi browser (Flatpak)
- `damian` Fedora 43 toolbox container
- Screenshot tool (grim + slurp)
- Hardware acceleration (VA-API via mesa)
- JetBrainsMono Nerd Font (terminal + Waybar)

## Fresh install

### Prerequisites

1. Generate SSH key and add to GitHub:

\`\`\`bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
\`\`\`

Then add the key at: https://github.com/settings/ssh/new

2. Run bootstrap:

\`\`\`bash
bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
\`\`\`

Bootstrap will:
- Clone this repository
- Run setup.sh (symlinks, Flatpaks, toolbox)
- Run packages.sh (system packages via rpm-ostree)

3. Reboot after bootstrap completes:

\`\`\`bash
systemctl reboot
\`\`\`

4. Verify hardware after reboot:

\`\`\`bash
bash ~/dotfiles-sway/scripts/check-hardware.sh
\`\`\`

## Keyboard layout

GB layout with Polish characters via PL variant. No switching needed.

## Bluetooth devices

Pair devices manually using bluetoothctl — the GUI applet may have connection issues:

\`\`\`bash
bluetoothctl
power on
scan on
pair <MAC_ADDRESS>
\`\`\`

## Structure

\`\`\`
dotfiles-sway/
├── sway/                    # Sway window manager config
├── waybar/                  # Waybar status bar config
├── foot/                    # Foot terminal config
├── mako/                    # Mako notification config
├── scripts/
│   └── check-hardware.sh   # Hardware verification script
├── setup.sh                 # Symlinks, Flatpaks, toolbox
├── packages.sh              # rpm-ostree system packages
└── bootstrap.sh             # Fresh install entry point
\`\`\`

# dotfiles-sway

Personal dotfiles for Fedora Atomic Sway setup.

## What's included

- Sway window manager config
- Waybar status bar config
- Foot terminal config
- XDG user directories
- Vivaldi browser (Flatpak)
- `damian` Fedora toolbox container

## Fresh install

**Prerequisites:**
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
> This will clone the repository and run `setup.sh` automatically.

## Structure
```
dotfiles-sway/
├── sway/         # Sway config
├── waybar/       # Waybar config
├── foot/         # Foot terminal config
├── scripts/      # Utility scripts
├── setup.sh      # Symlinks + Flatpaks + toolbox
└── bootstrap.sh  # Fresh install entry point
```

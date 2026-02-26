
#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles-sway"

echo "==> Creating config directories..."
mkdir -p ~/.config/sway
mkdir -p ~/.config/waybar
mkdir -p ~/.config/foot


# Symlinks
echo "==> Creating symlinks..."
ln -sf "$DOTFILES/sway/config"        ~/.config/sway/config
ln -sf "$DOTFILES/waybar/config"      ~/.config/waybar/config
ln -sf "$DOTFILES/foot/foot.ini"      ~/.config/foot/foot.ini
ln -sf "$DOTFILES/user-dirs.dirs"     ~/.config/user-dirs.dirs

# Flatpaks
echo "==> Installing Flatpaks..."
flatpak install -y flathub com.vivaldi.Vivaldi

echo "==> Done."

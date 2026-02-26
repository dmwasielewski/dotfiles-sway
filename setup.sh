
#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles-sway"

echo "==> Creating config directories..."
mkdir -p ~/.config/sway
mkdir -p ~/.config/waybar
mkdir -p ~/.config/foot
mkdir -p ~/.config/mako

echo "==> Creating User directories..."
mkdir -p ~/Pictures

echo "==> Suppressing system screenshot warning..."
mkdir -p ~/.config/sway/config.d
echo -n > ~/.config/sway/config.d/60-bindings-screenshot.conf

# Symlinks
echo "==> Creating symlinks..."
ln -sf "$DOTFILES/sway/config"        ~/.config/sway/config
ln -sf "$DOTFILES/waybar/config"      ~/.config/waybar/config
ln -sf "$DOTFILES/waybar/style.css"   ~/.config/waybar/style.css
ln -sf "$DOTFILES/foot/foot.ini"      ~/.config/foot/foot.ini
ln -sf "$DOTFILES/user-dirs.dirs"     ~/.config/user-dirs.dirs
ln -sf "$DOTFILES/mako/config" ~/.config/mako/config


# Toolbox
echo "==> Creating toolbox container..."
toolbox create --image registry.fedoraproject.org/fedora-toolbox:43 damian


# Flatpaks
echo "==> Installing Flatpaks..."
flatpak install -y flathub com.vivaldi.Vivaldi

echo "==> Done."

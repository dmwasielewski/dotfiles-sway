
#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles-sway"

echo "==> Creating config directories..."
mkdir -p ~/.config/sway
mkdir -p ~/.config/waybar
mkdir -p ~/.config/foot
mkdir -p ~/.config/mako
mkdir -p ~/.local/share/applications

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
ln -sf "$DOTFILES/applications/claude-ai.desktop" ~/.local/share/applications/claude-ai.desktop
ln -sf "$DOTFILES/applications/chatgpt.desktop" ~/.local/share/applications/chatgpt.desktop
ln -sf "$DOTFILES/applications/whatsapp.desktop" ~/.local/share/applications/whatsapp.desktop
update-desktop-database ~/.local/share/applications/

# Make scripts executable
chmod +x "$DOTFILES/scripts/"*.sh

# Toolbox
echo "==> Creating toolbox container..."
toolbox create --image registry.fedoraproject.org/fedora-toolbox:43 damian


# Flatpaks
echo "==> Installing Flatpaks..."
flatpak install -y flathub com.vivaldi.Vivaldi
flatpak install -y flathub io.mpv.Mpv
flatpak install -y flathub com.visualstudio.code
flatpak install -y flathub com.bitwarden.desktop
flatpak install -y flathub md.obsidian.Obsidian
flatpak install -y flathub com.spotify.Client
flatpak install -y flathub com.obsproject.Studio
flatpak install -y flathub org.jdownloader.JDownloader


# Fonts
echo "==> Installing JetBrainsMono Nerd Font..."
mkdir -p ~/.local/share/fonts
curl -OL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono
rm JetBrainsMono.zip
fc-cache -fv

echo "==> Installing Font Awesome..."
curl -OL https://github.com/FortAwesome/Font-Awesome/releases/latest/download/fontawesome-free-6.7.2-desktop.zip
unzip fontawesome-free-*.zip -d ~/.local/share/fonts/FontAwesome
rm fontawesome-free-*.zip
fc-cache -fv

# Distrobox 

# Security container
# NOTE: Run this manually after reboot (requires distrobox from packages.sh)
# bash "$DOTFILES/scripts/setup-security-container.sh"

echo "==> Creating security container..."
bash "$DOTFILES/scripts/setup-security-container.sh"

echo "==> Done."
 

#!/bin/bash
set -e

DOTFILES="$HOME/dotfiles-sway"
if [[ -f "$DOTFILES/scripts/lib-install.sh" ]]; then
    source "$DOTFILES/scripts/lib-install.sh"
    setup_logging "setup.sh"
fi

# Extract a zip with `unzip` when present, else fall back to python3's stdlib
# zipfile module (python3 ships in the Fedora base image). Phase-1 setup must NOT
# hard-depend on `unzip`: it is only layered later by packages.sh, so a fresh base
# image without it would otherwise never reach the step that installs it.
extract_zip() {
    local zip="$1" dest="$2"
    mkdir -p "$dest"
    if command -v unzip &>/dev/null; then
        unzip -oq "$zip" -d "$dest"
    elif command -v python3 &>/dev/null; then
        python3 -m zipfile -e "$zip" "$dest"
    else
        echo "WARNING: neither unzip nor python3 available — cannot extract $zip" >&2
        return 1
    fi
}

echo "==> Creating config directories..."
mkdir -p ~/.config/sway
mkdir -p ~/.config/waybar
mkdir -p ~/.config/foot
mkdir -p ~/.config/mako
mkdir -p ~/.config/environment.d
mkdir -p ~/.local/share/applications
mkdir -p ~/.claude

echo "==> Creating user directories..."
mkdir -p ~/Pictures

echo "==> Suppressing system screenshot warning..."
mkdir -p ~/.config/sway/config.d
echo -n > ~/.config/sway/config.d/60-bindings-screenshot.conf

# Symlinks
echo "==> Creating symlinks..."
ln -sf "$DOTFILES/sway/config"                                ~/.config/sway/config
ln -sf "$DOTFILES/sway/config.d/90-swayidle.conf"            ~/.config/sway/config.d/90-swayidle.conf
ln -sf "$DOTFILES/sway/config.d/90-bar.conf"                 ~/.config/sway/config.d/90-bar.conf
ln -sf "$DOTFILES/waybar/config"                              ~/.config/waybar/config
ln -sf "$DOTFILES/waybar/style.css"                           ~/.config/waybar/style.css
ln -sf "$DOTFILES/foot/foot.ini"                              ~/.config/foot/foot.ini
ln -sf "$DOTFILES/user-dirs.dirs"                             ~/.config/user-dirs.dirs
ln -sf "$DOTFILES/mako/config"                                ~/.config/mako/config
mkdir -p ~/.config/yazi
ln -sf "$DOTFILES/yazi/keymap.toml"                           ~/.config/yazi/keymap.toml
ln -sf "$DOTFILES/environment.d/locale.conf"            ~/.config/environment.d/locale.conf
ln -sf "$DOTFILES/.bashrc"                                    ~/.bashrc
ln -sf "$DOTFILES/applications/whispering-open.desktop"       ~/.local/share/applications/whispering-open.desktop
ln -sf "$DOTFILES/claude/settings.json"                        ~/.claude/settings.json
mkdir -p ~/.local/bin
ln -sf "$DOTFILES/scripts/deepseek-wrapper.sh"                 ~/.local/bin/deepseek
ln -sf "$DOTFILES/scripts/deepseek-wrapper.sh"                 ~/.local/bin/deepseek-tui
ln -sf "$DOTFILES/scripts/adguard-waybar.sh"                   ~/.local/bin/adguard-waybar
ln -sf "$DOTFILES/scripts/nordvpn-waybar.sh"                   ~/.local/bin/nordvpn-waybar
ln -sf "$DOTFILES/scripts/nordvpn-whitelist-domain.sh"         ~/.local/bin/nordvpn-whitelist-domain
ln -sf "$DOTFILES/scripts/updates-waybar.sh"                   ~/.local/bin/updates-waybar
ln -sf "$DOTFILES/scripts/updates-do.sh"                       ~/.local/bin/updates-do
ln -sf "$DOTFILES/scripts/updates-menu.sh"                     ~/.local/bin/updates-menu
ln -sf "$DOTFILES/scripts/power-menu.sh"                       ~/.local/bin/power-menu
ln -sf "$DOTFILES/scripts/close-focused-app.sh"               ~/.local/bin/close-focused-app
ln -sf "$DOTFILES/scripts/enter-damianf.sh"                    ~/.local/bin/damianf
ln -sf "$DOTFILES/scripts/enter-damianu.sh"                    ~/.local/bin/damianu
ln -sf "$DOTFILES/scripts/bat-wrapper.sh"                      ~/.local/bin/bat
ln -sf "$DOTFILES/scripts/fd-wrapper.sh"                       ~/.local/bin/fd
ln -sf "$DOTFILES/scripts/rg-wrapper.sh"                       ~/.local/bin/rg
mkdir -p ~/.npm-global/bin
ln -sf "$DOTFILES/scripts/deepseek-wrapper.sh"                 ~/.npm-global/bin/deepseek
ln -sf "$DOTFILES/scripts/deepseek-wrapper.sh"                 ~/.npm-global/bin/deepseek-tui
update-desktop-database ~/.local/share/applications/

# Make scripts executable
chmod +x "$DOTFILES/scripts/"*.sh
chmod +x "$DOTFILES/.githooks/"* 2>/dev/null || true

echo "==> Setting up Neovim..."
bash "$DOTFILES/scripts/setup-neovim-config.sh"

# yazi is not in Fedora's repos, so install it user-local from its GitHub release
# (no root/reboot). ffmpegthumbnailer for previews comes from packages.sh.
run_step_warn "YAZI_INSTALLED" "Setting up yazi" bash "$DOTFILES/scripts/setup-yazi.sh"

# Zed (GUI editor) is not in Fedora's repos and the Flathub build is an unofficial
# wrapper, so install the official upstream binary user-local from its GitHub
# release (no root/reboot). Launched on demand — no autostart/keybinding; Neovim
# stays the terminal editor. The asset is ~140 MB, so this can take a while.
run_step_warn "ZED_INSTALLED" "Setting up Zed" bash "$DOTFILES/scripts/setup-zed.sh"

# Use versioned git hooks from this repo, including the gitleaks pre-push check.
if git -C "$DOTFILES" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "$DOTFILES" config core.hooksPath .githooks
fi

# Toolbox — skip if already exists
echo "==> Creating toolbox container..."
HOST_FEDORA_VERSION="$(. /etc/os-release && printf '%s' "${VERSION_ID:-44}")"
TOOLBOX_VERSION="${TOOLBOX_VERSION:-$HOST_FEDORA_VERSION}"
TOOLBOX_CONTAINER="${TOOLBOX_CONTAINER:-damianf}"
TOOLBOX_IMAGE="${TOOLBOX_IMAGE:-registry.fedoraproject.org/fedora-toolbox:${TOOLBOX_VERSION}}"
if toolbox list | grep -q "$TOOLBOX_CONTAINER"; then
    echo "==> Toolbox '$TOOLBOX_CONTAINER' already exists — skipping."
else
    toolbox create --assumeyes --image "$TOOLBOX_IMAGE" "$TOOLBOX_CONTAINER"
fi

# Container engine for the dev containers (Podman/kind cannot run nested
# inside a rootless toolbox/distrobox, so the containers use the HOST engine
# as a remote — see containers.conf.d written by the container setup scripts).
run_step_warn "PODMAN_SOCKET" "Enabling host Podman socket for dev containers" \
    systemctl --user enable --now podman.socket

# Rootless kind needs cpuset (and cpu) cgroup delegation for the user manager.
if [[ -f /etc/systemd/system/user@.service.d/delegate.conf ]]; then
    step_done "CGROUP_DELEGATION"
else
    echo "==> Adding cgroup delegation for rootless kind (needs sudo)..."
    if sudo mkdir -p /etc/systemd/system/user@.service.d && \
       printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf >/dev/null; then
        sudo systemctl daemon-reload
        echo "    ✓ Delegation set — takes effect after the next login."
        step_done "CGROUP_DELEGATION"
    else
        echo "    ⚠ Could not write delegation — kind clusters may fail until you add it."
        step_failed "CGROUP_DELEGATION"
    fi
fi

# Flatpaks
echo "==> Installing Flatpaks..."
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo

install_flatpak_app() {
    local app_id="$1"

    if flatpak list --app --columns=application 2>/dev/null | grep -Fxq "$app_id"; then
        echo "==> Flatpak $app_id already installed — skipping"
    else
        flatpak install -y --user flathub "$app_id"
    fi
}

install_flatpak_app io.mpv.Mpv
install_flatpak_app com.visualstudio.code
install_flatpak_app com.bitwarden.desktop
install_flatpak_app md.obsidian.Obsidian
# Flathub rebased the plain org.mozilla.Thunderbird ID to the ESR build, so install
# that and apply the LC_TIME override to whatever variant actually got installed
# (discovered at runtime — never hardcode the ID).
install_flatpak_app org.mozilla.thunderbird_esr
tb_id="$("$DOTFILES/scripts/thunderbird-id.sh" 2>/dev/null || true)"
[[ -n "$tb_id" ]] && flatpak override --user --env=LC_TIME=en_GB.UTF-8 "$tb_id" || true
install_flatpak_app com.spotify.Client
install_flatpak_app com.obsproject.Studio
install_flatpak_app org.jdownloader.JDownloader
install_flatpak_app com.vixalien.sticky
install_flatpak_app org.libreoffice.LibreOffice
install_flatpak_app org.kde.kdenlive

echo "==> Installing Whispering Open from GitHub release..."
run_step_warn "WHISPERING_OPEN_SETUP" "Installing Whispering Open from GitHub release" \
    bash "$DOTFILES/scripts/setup-whispering-open.sh"

# Fonts
echo "==> Installing JetBrainsMono Nerd Font..."
mkdir -p ~/.local/share/fonts
if ls ~/.local/share/fonts/JetBrainsMono/*.ttf >/dev/null 2>&1; then
    echo "==> JetBrainsMono Nerd Font already installed — skipping download"
else
    curl -fL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o JetBrainsMono.zip
    extract_zip JetBrainsMono.zip ~/.local/share/fonts/JetBrainsMono
    rm -f JetBrainsMono.zip
    fc-cache -fv
fi

echo "==> Installing Font Awesome..."
if find ~/.local/share/fonts/FontAwesome -type f \( -name '*.otf' -o -name '*.ttf' \) 2>/dev/null | grep -q .; then
    echo "==> Font Awesome already installed — skipping download"
else
    FA_URL=$(curl -fsSL https://api.github.com/repos/FortAwesome/Font-Awesome/releases/latest | grep -o 'https://[^"]*desktop\.zip' | head -n1)
    if [ -z "$FA_URL" ]; then
        echo "WARNING: Could not resolve Font Awesome download URL — skipping. Install manually from https://fontawesome.com"
    else
        curl -fL "$FA_URL" -o FontAwesome.zip
        extract_zip FontAwesome.zip ~/.local/share/fonts/FontAwesome
        find ~/.local/share/fonts/FontAwesome -mindepth 2 -type f \( -name '*.otf' -o -name '*.ttf' \) -exec cp -f {} ~/.local/share/fonts/FontAwesome/ \;
        rm -f FontAwesome.zip
        fc-cache -fv
    fi
fi

# Set Firefox (Fedora Sway Atomic's base-image browser) as the default browser
xdg-settings set default-web-browser org.mozilla.firefox.desktop

echo "==> Done."
echo ""
echo "==> Next steps:"
echo "    1. Run packages.sh then reboot: bash ~/dotfiles-sway/packages.sh"
echo "    2. After reboot run: bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
echo "    3. After reboot run: bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
echo "    4. After reboot run: bash ~/dotfiles-sway/scripts/setup-security-container.sh"
print_state_summary

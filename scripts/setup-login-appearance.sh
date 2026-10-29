#!/bin/bash
# Run on the Fedora host; --check is read-only and also supports toolbox.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST=
[[ ! -d /run/host/etc ]] || HOST=/run/host
image=/usr/local/share/backgrounds/login.jpg
theme=/etc/sddm/themes/03-sway-fedora
drop=/etc/sddm.conf.d/10-login-wallpaper.conf
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
if [[ ${1:-} == --check ]]; then
    cmp -s "$ROOT/assets/login.jpg" "$HOST$image" &&
    grep -Fxq "background=$image" "$HOST$theme/theme.conf" &&
    grep -Fxq 'ThemeDir=/etc/sddm/themes' "$HOST$drop" &&
    grep -Fxq 'Current=03-sway-fedora' "$HOST$drop" &&
    cmp -s "$ROOT/swaylock/config" "$config_home/swaylock/config"
    exit $?
fi
mkdir -p "$config_home/swaylock"
if [[ -e "$config_home/swaylock/config" && ! -L "$config_home/swaylock/config" ]]; then
    cp -an "$config_home/swaylock/config" "$config_home/swaylock/config.before-dotfiles"
fi
ln -sfn "$ROOT/swaylock/config" "$config_home/swaylock/config"
if [[ -n "$HOST" ]]; then
    echo 'Lock configuration installed. Run this script on the host to install SDDM files.' >&2
    exit 1
fi
[[ -f /usr/share/sddm/themes/03-sway-fedora/Main.qml ]]
sudo install -Dm644 "$ROOT/assets/login.jpg" "$image"
sudo mkdir -p "$theme" /etc/sddm.conf.d
sudo cp -a /usr/share/sddm/themes/03-sway-fedora/. "$theme/"
printf '[General]\nbackground=%s\n' "$image" | sudo tee "$theme/theme.conf" >/dev/null
printf '[Theme]\nThemeDir=/etc/sddm/themes\nCurrent=03-sway-fedora\n' | sudo tee "$drop" >/dev/null
sudo restorecon -R /etc/sddm /etc/sddm.conf.d /usr/local/share/backgrounds
echo 'Login and lock wallpaper installed. No session restart required for the next lock.'

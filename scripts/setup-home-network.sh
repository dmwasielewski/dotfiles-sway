#!/bin/bash
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
config="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/home-network.json"
if [[ ! -f "$config" ]]; then
    echo 'Home automation not opted in; restore private home-network.json or enroll home Wi-Fi.'
    exit 0
fi
python3 "$DOTFILES/scripts/home-network.py" check
mkdir -p "$HOME/.config/systemd/user"
ln -sfn "$DOTFILES/systemd/home-network.service" "$HOME/.config/systemd/user/home-network.service"
systemctl --user daemon-reload
if [[ ${1:-} == --install-only ]]; then
    systemctl --user enable home-network.service
else
    systemctl --user enable --now home-network.service
fi

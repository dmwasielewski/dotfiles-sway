#!/bin/bash
# Install + enable the phase-2 user service so it resumes after the reboot.
# Enables linger so the service can run without an interactive login.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.config/systemd/user"
mkdir -p "$dest"
ln -sf "$HERE/../systemd/user/dotfiles-phase2.service" "$dest/dotfiles-phase2.service"
systemctl --user daemon-reload
systemctl --user enable dotfiles-phase2.service
sudo loginctl enable-linger "$USER"
echo "phase-2 service enabled (linger on)"

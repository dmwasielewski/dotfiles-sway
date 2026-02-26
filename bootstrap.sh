#!/bin/bash
set -e

GITHUB_USER="dmwasielewski"
REPO="dotfiles-sway"

echo "==> Cloning dotfiles..."
git clone git@github.com:$GITHUB_USER/$REPO.git ~/dotfiles-sway

echo "==> Running setup (symlinks, flatpaks, toolbox)..."
bash ~/dotfiles-sway/setup.sh

echo "==> Installing system packages (reboot required after)..."
bash ~/dotfiles-sway/packages.sh

echo ""
echo "=========================================="
echo " Reboot now: systemctl reboot"
echo " After reboot verify: bash ~/dotfiles-sway/scripts/check-hardware.sh"
echo "=========================================="

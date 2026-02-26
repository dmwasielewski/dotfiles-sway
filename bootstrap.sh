#!/bin/bash
set -e

GITHUB_USER="dmwasielewski"
REPO="dotfiles-sway"

echo "==> Cloning dotfiles..."
git clone git@github.com:$GITHUB_USER/$REPO.git ~/dotfiles-sway

echo "==> Running setup..."
bash ~/dotfiles-sway/setup.sh

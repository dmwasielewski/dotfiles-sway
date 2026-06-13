#!/bin/bash
# P0 launcher for an unattended dotfiles-sway install. The USB holds only the
# encrypted secrets vault (LUKS, discovered by PARTLABEL); the repo is cloned
# from GitHub. Run this once on a fresh Fedora Sway Atomic install (plug the USB
# in first). It clones the repo, unlocks the vault, takes one sudo credential,
# harvests the secrets to on-disk staging, locks the vault, and starts the
# orchestrator (P0..P1, which reboots; the phase-2 service resumes P2..P3).
set -euo pipefail
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/dmwasielewski/dotfiles-sway.git}"
DEST="$HOME/dotfiles-sway"
STAGE="$HOME/.local/state/dotfiles-secrets"

echo "==> cloning $REPO_URL"
[[ -d "$DEST/.git" ]] || git clone "$REPO_URL" "$DEST"
VAULT="$DEST/scripts/vault/vault"

echo "==> unlocking the secrets vault (USB)"
"$VAULT" unlock

echo "==> caching one sudo credential for provisioning"
sudo -v

echo "==> harvesting secrets to $STAGE"
mkdir -p "$STAGE"; chmod 700 "$STAGE"
cp -a "$HOME/.vault/." "$STAGE/"
chmod -R go-rwx "$STAGE"
"$VAULT" lock

echo "==> starting the orchestrator"
exec "$DEST/orchestrate.sh" run

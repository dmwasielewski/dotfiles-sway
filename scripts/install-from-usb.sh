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
# Ask the vault library where the vault is rather than repeating its default:
# hardcoding "$HOME/.vault" here meant a VAULT_MOUNT override unlocked one place
# and harvested from another. If a stale empty ~/.vault existed, the copy would
# succeed, stage nothing, and the install would carry on with no secrets at all.
# shellcheck source=scripts/vault/lib-vault.sh
source "$DEST/scripts/vault/lib-vault.sh"
vault_is_unlocked || { echo "install: vault is not mounted at $VAULT_MOUNT — aborting" >&2; exit 1; }

mkdir -p "$STAGE"; chmod 700 "$STAGE"
cp -a "$VAULT_MOUNT/." "$STAGE/"
chmod -R go-rwx "$STAGE"

# Prove the harvest actually produced something before locking the vault again;
# after `vault lock` the source is gone and an empty staging is unrecoverable
# without the USB and the passphrase.
staged_count="$(find "$STAGE" -type f | wc -l)"
if [[ "$staged_count" -eq 0 ]]; then
    echo "install: harvested 0 files from $VAULT_MOUNT — aborting before locking the vault" >&2
    exit 1
fi
echo "==> harvested $staged_count file(s)"
"$VAULT" lock

echo "==> starting the orchestrator"
exec "$DEST/orchestrate.sh" run

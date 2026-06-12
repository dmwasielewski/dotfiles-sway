#!/bin/bash
# Encrypt the unlocked vault into a single age file for the private-repo backup.
# Plaintext NEVER leaves the machine: we tar the mount and pipe straight into age.
# Usage: backup-vault.sh [output.age]   (default: ./vault.age)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vault/lib-vault.sh
source "$HERE/lib-vault.sh"
out="${1:-vault.age}"

vault_is_unlocked || { echo "vault: unlock first (vault unlock)" >&2; exit 1; }
command -v age >/dev/null || { echo "age not installed (packages.sh adds it)" >&2; exit 1; }

# age with a passphrase (symmetric). tar -C the mount so paths are relative.
tar -C "$VAULT_MOUNT" -cf - . | age -p -o "$out"
echo "vault: encrypted backup written to $out (ciphertext only)"
echo "Restore: age -d $out | tar -C <mounted-vault> -xf -"

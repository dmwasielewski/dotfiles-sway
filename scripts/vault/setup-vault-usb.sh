#!/bin/bash
# DESTRUCTIVE: turn a block device into a LUKS2 secrets vault. Re-confirms the
# target and requires typing the device path to proceed. Run on the host as root.
# Usage: sudo setup-vault-usb.sh /dev/sdX
#
# Uses parted (Fedora base) for partitioning, cryptsetup (base) for LUKS2, and
# mkfs.ext4. The GPT partition is NAMED so the vault is discovered by PARTLABEL,
# never a hardcoded /dev path.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vault/lib-vault.sh
source "$HERE/lib-vault.sh"
dev="${1:?usage: setup-vault-usb.sh /dev/sdX}"

[[ "$(id -u)" -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
[[ -b "$dev" ]] || { echo "not a block device: $dev" >&2; exit 1; }

echo "About to ERASE and re-create as a LUKS2 vault:"
lsblk -o NAME,SIZE,TYPE,RM,TRAN,MOUNTPOINT,MODEL "$dev"
echo
echo "Type the device path EXACTLY ($dev) to confirm destruction:"
read -r confirm
[[ "$confirm" == "$dev" ]] || { echo "aborted"; exit 1; }

# Unmount any currently-mounted partitions of the target (e.g. an auto-mounted
# vfat) so partitioning doesn't fail on a busy device.
while read -r name mp; do
    [[ -n "$mp" ]] || continue
    echo "unmounting /dev/$name ($mp)"
    umount "/dev/$name" 2>/dev/null || umount -l "/dev/$name" 2>/dev/null || true
done < <(lsblk -rno NAME,MOUNTPOINT "$dev" | tail -n +2)

# Single GPT partition, named for label-based discovery.
parted -s "$dev" mklabel gpt
parted -s "$dev" mkpart "$VAULT_PARTLABEL" ext4 1MiB 100%
udevadm settle 2>/dev/null || partprobe "$dev" 2>/dev/null || true
sleep 1

part="$(lsblk -rno NAME,PARTLABEL "$dev" | awk -v l="$VAULT_PARTLABEL" '$2==l{print "/dev/"$1; exit}')"
[[ -n "$part" ]] || { echo "partition not found after create" >&2; exit 1; }

echo "Set the LUKS passphrase for the vault:"
cryptsetup luksFormat --type luks2 "$part"
echo "Unlock to create the filesystem:"
cryptsetup open "$part" "$VAULT_MAPPER"
mkfs.ext4 -q -L "$VAULT_LABEL" "/dev/mapper/$VAULT_MAPPER"

mnt="$(mktemp -d)"
mount "/dev/mapper/$VAULT_MAPPER" "$mnt"
mkdir -p "$mnt"/{ai,dev/ssh,vpn,accounts,install}
cat > "$mnt/README.md" <<'README'
# Secrets vault

One file = one secret. Edit/add freely; the volume is LUKS-encrypted at rest.

Layout:
- ai/        AI service API keys (prefer non-expiring keys), e.g. anthropic.key, openai.key, gemini.key, deepseek.key, qwen.key, perplexity.key, kimi.key
- dev/       github-token, ssh/{id_ed25519,id_ed25519.pub}
- vpn/       nordvpn-token
- accounts/  accounts.env (KEY=VALUE app/account passwords — reference only; GUI logins stay manual)
- install/   manifest.toml (maps install-consumed secrets to destinations)

Use:
  vault unlock            # cryptsetup open + mount (asks passphrase)
  vault get ai/anthropic.key
  vault list
  eval "$(vault env ai)"  # load a group into the current shell on demand
  vault lock

Backup (B2):
  backup-vault.sh ~/vault.age      # age ciphertext for the private repo
  clone-vault.sh ~/.vault /run/media/$USER/VAULT2   # second LUKS USB
README
chmod -R go-rwx "$mnt"

umount "$mnt"; rmdir "$mnt"
cryptsetup close "$VAULT_MAPPER"
echo "vault: LUKS2 vault ready on $dev (PARTLABEL=$VAULT_PARTLABEL, FS label=$VAULT_LABEL)"
echo "Next: 'vault unlock', then fill in the secret files (see README.md)."

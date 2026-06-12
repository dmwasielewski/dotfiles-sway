#!/bin/bash
# HOST-RUN, ROOT. Clone one loopback vault into a second one via clone-vault.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLONE="$HERE/../../../scripts/vault/clone-vault.sh"
SRC_IMG="${IMG:-/var/tmp/vault-test.img}"; SRC_MAP="vault"
DST_IMG="/var/tmp/vault-test2.img"; DST_MAP="vault2"

# dest: a fresh empty LUKS2 ext4 image
rm -f "$DST_IMG"; truncate -s 64M "$DST_IMG"
echo -n testpass | cryptsetup luksFormat --type luks2 "$DST_IMG" -
echo -n testpass | cryptsetup open "$DST_IMG" "$DST_MAP" -
mkfs.ext4 -q "/dev/mapper/$DST_MAP"

s="$(mktemp -d)"; d="$(mktemp -d)"
echo -n testpass | cryptsetup open "$SRC_IMG" "$SRC_MAP" -
mount "/dev/mapper/$SRC_MAP" "$s"; mount "/dev/mapper/$DST_MAP" "$d"
bash "$CLONE" "$s" "$d"
val="$(cat "$d/ai/anthropic.key")"
umount "$s"; umount "$d"; cryptsetup close "$SRC_MAP"; cryptsetup close "$DST_MAP"
rmdir "$s" "$d"; rm -f "$DST_IMG"
[[ "$val" == "sk-ant" ]] && echo "PASS: clone copied the secret" || { echo "FAIL"; exit 1; }

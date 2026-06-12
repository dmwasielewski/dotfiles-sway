#!/bin/bash
# HOST-RUN, ROOT. Build a loopback-backed LUKS2 vault to exercise the device
# layer WITHOUT real hardware. Passphrase for tests: "testpass".
set -euo pipefail
IMG="${IMG:-/var/tmp/vault-test.img}"
MAP="${MAP:-vault}"   # matches VAULT_MAPPER default
rm -f "$IMG"; truncate -s 64M "$IMG"
echo -n testpass | cryptsetup luksFormat --type luks2 "$IMG" -
echo -n testpass | cryptsetup open "$IMG" "$MAP" -
mkfs.ext4 -q -L VAULT "/dev/mapper/$MAP"
mnt="$(mktemp -d)"; mount "/dev/mapper/$MAP" "$mnt"
mkdir -p "$mnt/ai"; echo "sk-ant" > "$mnt/ai/anthropic.key"
umount "$mnt"; rmdir "$mnt"; cryptsetup close "$MAP"
echo "loopback vault image at $IMG (passphrase: testpass)"

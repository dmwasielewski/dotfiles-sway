#!/bin/bash
# HOST-RUN, ROOT. Verify open+mount+read+close against the loopback image.
set -euo pipefail
IMG="${IMG:-/var/tmp/vault-test.img}"; MAP="${MAP:-vault}"; MNT="$(mktemp -d)"
echo -n testpass | cryptsetup open "$IMG" "$MAP" -
mount "/dev/mapper/$MAP" "$MNT"
val="$(cat "$MNT/ai/anthropic.key")"
umount "$MNT"; cryptsetup close "$MAP"; rmdir "$MNT"
[[ "$val" == "sk-ant" ]] && echo "PASS: read secret from loopback vault" || { echo "FAIL"; exit 1; }

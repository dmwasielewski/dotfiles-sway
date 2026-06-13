#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$DIR/scripts/lib-orchestrate.sh"
out="$(provisioning_sudoers_content damian)"
assert_contains "$out" "damian ALL=(ALL) NOPASSWD:" "names the user"
assert_contains "$out" "/usr/bin/rpm-ostree" "allows rpm-ostree"
assert_contains "$out" "/usr/bin/systemctl"  "allows systemctl"
assert_contains "$out" "/usr/sbin/usermod"   "allows usermod"
# must NOT be a blanket ALL command grant
[[ "$out" != *"NOPASSWD: ALL"* ]] && echo "  ok: not a blanket grant" || { echo "  FAIL: blanket"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
assert_summary

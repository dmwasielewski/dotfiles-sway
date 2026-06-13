#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PI() { bash -c 'source "$1"; profile_includes "$2" "$3"' _ "$DIR/scripts/verify.sh" "$@"; }
PI phase1 base        && echo "  ok: phase1 base"        || { echo FAIL; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
PI phase1 kvm         && { echo "  FAIL: phase1 kvm";   ASSERT_FAIL=$((ASSERT_FAIL+1)); } || echo "  ok: phase1 excludes kvm"
PI post-reboot kvm    && echo "  ok: post-reboot kvm"    || { echo FAIL; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
PI full optional      && echo "  ok: full optional"      || { echo FAIL; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
assert_summary

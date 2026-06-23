#!/bin/bash
# staged_from_json: detect a staged rpm-ostree deployment (pending reboot) from
# `rpm-ostree status --json`. The real os_staged() pipes rpm-ostree into it; this
# unit test feeds fixed JSON so it needs no rpm-ostree and no network.
#
# Regression: the previous os_staged() grepped `rpm-ostree status` for the literal
# string "(staged)", which current rpm-ostree (F44) does not print — so a genuinely
# staged update was never detected and showed amber instead of red "reboot to apply".
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/lib-updates.sh
source "$DIR/scripts/lib-updates.sh"

# A staged deployment: top of list, not booted, staged=true → reboot pending.
staged_json='{"deployments":[
  {"booted":false,"staged":true,"version":"44.20260623.0"},
  {"booted":true,"staged":false,"version":"44.20260622.0"}
]}'
out="$(printf '%s' "$staged_json" | staged_from_json)"
assert_eq "$out" "1" "reports 1 when a staged (pending-reboot) deployment exists"

# No staged deployment: booted is current, nothing pending.
clean_json='{"deployments":[
  {"booted":true,"staged":false,"version":"44.20260623.0"},
  {"booted":false,"staged":false,"version":"44.20260622.0"}
]}'
out="$(printf '%s' "$clean_json" | staged_from_json)"
assert_eq "$out" "0" "reports 0 when no deployment is staged"

# Garbage / empty input must degrade to 0, never crash or echo nothing.
out="$(printf '%s' "" | staged_from_json)"
assert_eq "$out" "0" "reports 0 on empty input"

assert_summary

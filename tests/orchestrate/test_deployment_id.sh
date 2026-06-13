#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$DIR/scripts/lib-orchestrate.sh"
out="$(deployment_id_from_json < "$(dirname "$0")/fixtures/rpm-ostree-status.json")"
assert_eq "$out" "aaaa1111" "parses the booted deployment checksum"
assert_summary

#!/bin/bash
# The default key-server templates must survive bash parsing intact: a "{FPR}"
# inside ${KEY_SOURCES:-…} once ended the expansion early and broke both URLs.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset KEY_SOURCES
# shellcheck disable=SC1090
source <(sed '/^\[\[ \$# -gt 0 \]\]/,$d' "$DIR/scripts/container-key-refresh.sh")
read -ra srcs <<< "$KEY_SOURCES"
assert_eq "${#srcs[@]}" 2 "two default key servers"
for s in "${srcs[@]}"; do
    assert_contains "$s" "https://" "default source is https: $s"
    [[ "$s" == *"{FPR}" ]] && r=0 || r=1
    assert_rc "$r" 0 "template ends in {FPR}: $s"
    url="${s//\{FPR\}/ABC}"
    [[ "$url" != *"{"* && "$url" != *"}"* ]] && r=0 || r=1
    assert_rc "$r" 0 "no brace left after substitution"
done
assert_summary

#!/bin/bash
source "$(dirname "$0")/assert.sh"
PARSE="$(dirname "$0")/../../scripts/vault/vault-parse-manifest.py"
out="$(python3 "$PARSE" "$(dirname "$0")/fixtures/manifest.toml")"
# TSV columns: action \t source \t key=val pairs... (trailing pairs sorted by key)
assert_contains "$out" $'env\tai/anthropic.key\tname=ANTHROPIC_API_KEY' "env row"
assert_contains "$out" $'file\tai/gemini.key\tdest=~/.config/voice-type/gemini-api-key\tmode=0600' "file row"
assert_contains "$out" $'command\tvpn/nordvpn-token\tcommand=nordvpn login --token {value}' "command row"
assert_summary

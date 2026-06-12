#!/bin/bash
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../../scripts/vault/lib-vault.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export VAULT_MOUNT="$tmp"
mkdir -p "$tmp/ai" "$tmp/dev"
printf 'sk-ant\n'    > "$tmp/ai/anthropic.key"
printf 'sk-openai\n' > "$tmp/ai/openai.key"
printf 'ghp_x\n'     > "$tmp/dev/github-token"

out="$(vault_env ai)"
assert_contains "$out" "export ANTHROPIC_API_KEY='sk-ant'"  "anthropic exported"
assert_contains "$out" "export OPENAI_API_KEY='sk-openai'"  "openai exported"

devout="$(vault_env dev)"
assert_contains "$devout" "export GITHUB_TOKEN='ghp_x'"     "token var name (no _API_KEY)"
assert_summary

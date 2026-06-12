#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"     # repo root
source "$DIR/scripts/vault/lib-vault.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export VAULT_MOUNT="$tmp"
mkdir -p "$tmp/ai" "$tmp/dev/ssh"
printf 'sk-ant-123\n' > "$tmp/ai/anthropic.key"
printf 'ghp_abc\n'    > "$tmp/dev/github-token"
printf '# readme\n'   > "$tmp/README.md"

# get returns the value (trailing newline stripped)
assert_eq "$(vault_get ai/anthropic.key)" "sk-ant-123" "get reads a secret"
# get on a missing file fails
( vault_get ai/nope.key >/dev/null 2>&1 ); assert_rc "$?" "1" "get missing fails"
# list shows secret paths, not README
out="$(vault_list)"
assert_contains "$out" "ai/anthropic.key" "list includes secret"
assert_contains "$out" "dev/github-token" "list includes token"
[[ "$out" != *"README.md"* ]] && echo "  ok: list excludes README" || { echo "  FAIL: README listed"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }

# CLI path (dispatcher) — added in Task 5
VAULT="$DIR/scripts/vault/vault"
if [[ -x "$VAULT" ]]; then
    assert_eq "$(VAULT_MOUNT="$tmp" "$VAULT" get ai/anthropic.key)" "sk-ant-123" "cli get"
    assert_contains "$(VAULT_MOUNT="$tmp" "$VAULT" list)" "dev/github-token" "cli list"
fi

assert_summary

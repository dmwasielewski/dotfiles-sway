#!/bin/bash
source "$(dirname "$0")/assert.sh"
GUARD="$(dirname "$0")/../../scripts/vault/vault-precommit-guard.sh"
# guard reads staged file list on stdin; exits 0 only if every path is vault.age
echo "vault.age" | bash "$GUARD" >/dev/null 2>&1; assert_rc "$?" "0" "accepts vault.age only"
printf 'vault.age\nai/anthropic.key\n' | bash "$GUARD" >/dev/null 2>&1; assert_rc "$?" "1" "rejects a plaintext secret"
printf 'README.md\n' | bash "$GUARD" >/dev/null 2>&1; assert_rc "$?" "1" "rejects anything else"
printf '' | bash "$GUARD" >/dev/null 2>&1; assert_rc "$?" "0" "empty staged set is fine"
assert_summary

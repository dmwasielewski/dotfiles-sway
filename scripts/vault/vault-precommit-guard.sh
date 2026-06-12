#!/bin/bash
# Pre-commit guard for the PRIVATE dotfiles-secrets repo: the only path allowed
# in a commit is vault.age. Reads staged paths on stdin (one per line). Install
# in that repo as .git/hooks/pre-commit:
#   git diff --cached --name-only | bash scripts/vault/vault-precommit-guard.sh
set -uo pipefail
bad=0
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" != "vault.age" ]]; then
        echo "REFUSED: only vault.age may be committed (got: $path)" >&2
        bad=1
    fi
done
exit "$bad"

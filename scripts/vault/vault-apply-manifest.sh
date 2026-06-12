#!/bin/bash
# Apply a vault manifest: plant secrets into their destinations. Reads secrets
# from $VAULT_MOUNT, writes into $HOME. Never prints secret values.
# Actions: env (append export to ~/.bashrc.d/ai-keys.bash), file (copy to dest,
# chmod), command (run a login command with {value} substituted).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vault/lib-vault.sh
source "$HERE/lib-vault.sh"

MANIFEST="${1:?usage: vault-apply-manifest.sh manifest.toml}"
ENV_FILE="$HOME/.bashrc.d/ai-keys.bash"
# Test hook: a runner that records the final command instead of executing it.
RUNNER="${VAULT_CMD_RUNNER:-}"

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

run_command() { # $1 = command template with literal {value}; $2 = secret value
    local cmd="${1//\{value\}/$2}"
    if [[ -n "$RUNNER" ]]; then "$RUNNER" "$cmd"; return; fi
    bash -c "$cmd"
}

mkdir -p "$(dirname "$ENV_FILE")"; touch "$ENV_FILE"; chmod 600 "$ENV_FILE"

python3 "$HERE/vault-parse-manifest.py" "$MANIFEST" | while IFS=$'\t' read -r action source rest1 rest2; do
    declare -A kv=()
    for col in "$rest1" "$rest2"; do
        [[ -n "$col" ]] && kv["${col%%=*}"]="${col#*=}"
    done
    value="$(vault_get "$source")" || { echo "vault-apply: missing $source" >&2; unset kv; continue; }
    case "$action" in
        env)
            name="${kv[name]}"
            # idempotent: drop any prior line for this var, then append
            grep -v "^export ${name}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
            mv "$ENV_FILE.tmp" "$ENV_FILE"
            printf "export %s='%s'\n" "$name" "$value" >> "$ENV_FILE"
            ;;
        file)
            dest="$(expand_tilde "${kv[dest]}")"; mode="${kv[mode]:-0600}"
            mkdir -p "$(dirname "$dest")"
            printf '%s\n' "$value" > "$dest"; chmod "$mode" "$dest"
            ;;
        command)
            run_command "${kv[command]}" "$value"
            ;;
        *) echo "vault-apply: unknown action: $action" >&2 ;;
    esac
    unset kv
done

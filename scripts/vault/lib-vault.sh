#!/bin/bash
# Shared vault library. Config + device resolution + non-privileged data layer.
# Source this; do not execute. No secret value is ever logged here.

VAULT_LABEL="${VAULT_LABEL:-VAULT}"        # filesystem label inside the LUKS volume
VAULT_PARTLABEL="${VAULT_PARTLABEL:-vault}" # GPT partition name set at setup time
VAULT_MAPPER="${VAULT_MAPPER:-vault}"      # device-mapper name when unlocked
VAULT_MOUNT="${VAULT_MOUNT:-$HOME/.vault}" # mountpoint (overridable in tests)

# Resolve the vault's LUKS partition by its GPT PARTLABEL — never a hardcoded
# /dev path. Echoes /dev/<name> or nothing.
vault_device() {
    lsblk -rno NAME,PARTLABEL 2>/dev/null \
        | awk -v l="$VAULT_PARTLABEL" '$2==l {print "/dev/"$1; exit}'
}

vault_is_unlocked() { [[ -e "/dev/mapper/$VAULT_MAPPER" ]] && mountpoint -q "$VAULT_MOUNT"; }

# --- data layer (operates on $VAULT_MOUNT; no privileges) ---
vault_get() { # $1 = path relative to vault root
    local f="$VAULT_MOUNT/$1"
    [[ -f "$f" ]] || { echo "vault: no such secret: $1" >&2; return 1; }
    # strip a single trailing newline, preserve the rest verbatim
    printf '%s' "$(cat "$f")"
}

vault_list() {
    [[ -d "$VAULT_MOUNT" ]] || { echo "vault: not mounted" >&2; return 1; }
    ( cd "$VAULT_MOUNT" && find . -type f \
        ! -name 'README.md' ! -path './install/*' \
        | sed 's|^\./||' | sort )
}

# Map a secret filename to its conventional env var name.
# anthropic.key -> ANTHROPIC_API_KEY ; github-token -> GITHUB_TOKEN
vault_env_varname() { # $1 = filename (e.g. anthropic.key, github-token)
    local base="${1%.key}"
    base="${base//-/_}"
    local upper; upper="$(printf '%s' "$base" | tr '[:lower:]' '[:upper:]')"
    case "$upper" in
        *_TOKEN) printf '%s' "$upper" ;;
        *)       printf '%s_API_KEY' "$upper" ;;
    esac
}

# Print `export NAME='value'` lines for every secret in a group dir. Use as:
#   eval "$(vault env ai)"
vault_env() { # $1 = group (subdirectory)
    local dir="$VAULT_MOUNT/$1"
    [[ -d "$dir" ]] || { echo "vault: no such group: $1" >&2; return 1; }
    local f name val
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        name="$(vault_env_varname "$(basename "$f")")"
        val="$(cat "$f")"
        printf "export %s='%s'\n" "$name" "$val"
    done
}

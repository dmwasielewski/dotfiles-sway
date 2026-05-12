#!/bin/bash
# configure-shellgpt.sh — non-interactive ShellGPT API configuration
# Secrets are loaded from private files or environment variables, never from git.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shell_gpt"
CONFIG_FILE="$CONFIG_DIR/.sgptrc"
BASHRC_D="$HOME/.bashrc.d"
ENV_LOADER="$BASHRC_D/shellgpt-gemini.bash"
LOCAL_BIN="$HOME/.local/bin"
SGPT_WRAPPER="$LOCAL_BIN/sgpt"
SGPT_REAL_BIN="$LOCAL_BIN/sgpt-cli"
VOICE_GEMINI_KEY_FILE="$HOME/.config/voice-type/gemini-api-key"

load_env_file() {
    local file="$1"
    [[ -r "$file" ]] || return 0
    set -a
    # shellcheck source=/dev/null
    source "$file"
    set +a
}

load_env_file "$HOME/.config/ai/api.env"
load_env_file "$HOME/.config/shell_gpt/credentials.env"
load_env_file "$HOME/.bashrc.d/ai-keys.bash"

PROVIDER="${SHELLGPT_PROVIDER:-auto}"
OPENAI_STYLE_API_KEY="${SHELLGPT_API_KEY:-${OPENAI_API_KEY:-}}"
GEMINI_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
if [[ -z "$GEMINI_API_KEY" && -r "$VOICE_GEMINI_KEY_FILE" ]]; then
    GEMINI_API_KEY="$(tr -d '\r\n' < "$VOICE_GEMINI_KEY_FILE")"
fi

PLACEHOLDER_KEY="missing-shellgpt-api-key"
DEFAULT_MODEL_FALLBACK="gpt-4o"
USE_LITELLM_FALLBACK="false"
GEMINI_PRIMARY_MODEL="${SHELLGPT_GEMINI_PRIMARY_MODEL:-gemini/gemini-3.1-flash-lite}"
GEMINI_FALLBACK_MODEL="${SHELLGPT_GEMINI_FALLBACK_MODEL:-gemini/gemini-2.5-flash}"
API_KEY="$OPENAI_STYLE_API_KEY"
SHELLGPT_PLACEHOLDER_CONFIG=false

if [[ "$PROVIDER" == "gemini" || ( "$PROVIDER" == "auto" && -n "$GEMINI_API_KEY" ) ]]; then
    if [[ -z "$GEMINI_API_KEY" ]]; then
        API_KEY="$PLACEHOLDER_KEY"
        SHELLGPT_PLACEHOLDER_CONFIG=true
        echo "SHELLGPT_PROVIDER=gemini but no Gemini API key source was found."
    else
        API_KEY="litellm-provider-env"
        DEFAULT_MODEL_FALLBACK="$GEMINI_PRIMARY_MODEL"
        USE_LITELLM_FALLBACK="true"
        echo "Using Gemini API key source shared with voice typing via LiteLLM."
    fi
elif [[ "$PROVIDER" == "openai" || ( "$PROVIDER" == "auto" && -n "$API_KEY" ) ]]; then
    if [[ -z "$API_KEY" ]]; then
        API_KEY="$PLACEHOLDER_KEY"
        SHELLGPT_PLACEHOLDER_CONFIG=true
        echo "SHELLGPT_PROVIDER=openai but no OpenAI-compatible API key source was found."
    else
        echo "Using OpenAI-compatible ShellGPT API key source."
    fi
elif [[ "$PROVIDER" == "anthropic" || ( "$PROVIDER" == "auto" && -n "${ANTHROPIC_API_KEY:-}" ) ]]; then
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        API_KEY="$PLACEHOLDER_KEY"
        SHELLGPT_PLACEHOLDER_CONFIG=true
        echo "SHELLGPT_PROVIDER=anthropic but ANTHROPIC_API_KEY was not found."
    else
        API_KEY="litellm-provider-env"
        DEFAULT_MODEL_FALLBACK="anthropic/claude-sonnet-4-20250514"
        USE_LITELLM_FALLBACK="true"
        echo "Using ANTHROPIC_API_KEY from private environment with LiteLLM."
    fi
elif [[ "$PROVIDER" != "auto" ]]; then
    API_KEY="$PLACEHOLDER_KEY"
    SHELLGPT_PLACEHOLDER_CONFIG=true
    echo "Unsupported SHELLGPT_PROVIDER='$PROVIDER'; expected auto, gemini, openai, or anthropic."
elif [[ -n "$API_KEY" ]]; then
    echo "Using OpenAI-compatible ShellGPT API key source."
else
    API_KEY="$PLACEHOLDER_KEY"
    SHELLGPT_PLACEHOLDER_CONFIG=true
    echo "No ShellGPT API key source found; writing non-interactive placeholder config."
    echo "Supported private sources: ~/.config/voice-type/gemini-api-key, GEMINI_API_KEY, GOOGLE_API_KEY, OPENAI_API_KEY, SHELLGPT_API_KEY, ANTHROPIC_API_KEY, ~/.config/ai/api.env, ~/.config/shell_gpt/credentials.env, ~/.bashrc.d/ai-keys.bash"
fi

API_BASE_URL="${SHELLGPT_API_BASE_URL:-${API_BASE_URL:-default}}"
DEFAULT_MODEL="${SHELLGPT_DEFAULT_MODEL:-${DEFAULT_MODEL:-$DEFAULT_MODEL_FALLBACK}}"
USE_LITELLM="${SHELLGPT_USE_LITELLM:-${USE_LITELLM:-$USE_LITELLM_FALLBACK}}"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

umask 077
cat > "$CONFIG_FILE" <<EOF
OPENAI_API_KEY=$API_KEY
API_BASE_URL=$API_BASE_URL
DEFAULT_MODEL=$DEFAULT_MODEL
REQUEST_TIMEOUT=60
DEFAULT_COLOR=magenta
DEFAULT_EXECUTE_SHELL_CMD=false
DISABLE_STREAMING=false
CODE_THEME=default
OPENAI_USE_FUNCTIONS=true
SHOW_FUNCTIONS_OUTPUT=false
USE_LITELLM=$USE_LITELLM
SHELL_INTERACTION=true
OS_NAME=auto
SHELL_NAME=auto
EOF

chmod 600 "$CONFIG_FILE"

install_sgpt_wrapper() {
    mkdir -p "$LOCAL_BIN"

    is_stock_sgpt_launcher() {
        local path="$1"
        grep -q 'from sgpt import cli' "$path" 2>/dev/null && ! grep -q 'SGPT_REAL_BIN' "$path" 2>/dev/null
    }

    if [[ -x "$SGPT_WRAPPER" ]] && grep -q 'from sgpt import cli' "$SGPT_WRAPPER" 2>/dev/null && [[ ! -x "$SGPT_REAL_BIN" ]]; then
        mv "$SGPT_WRAPPER" "$SGPT_REAL_BIN"
        chmod +x "$SGPT_REAL_BIN"
    fi

    if [[ -x "$SGPT_WRAPPER" ]] && ! grep -q 'SGPT_REAL_BIN' "$SGPT_WRAPPER" 2>/dev/null; then
        if is_stock_sgpt_launcher "$SGPT_WRAPPER"; then
            :
        elif [[ -x "$SGPT_REAL_BIN" ]]; then
            echo "==> Existing unmanaged sgpt wrapper detected at $SGPT_WRAPPER — preserving it."
            return 0
        fi
        if ! is_stock_sgpt_launcher "$SGPT_WRAPPER"; then
            echo "==> Existing unmanaged sgpt wrapper detected at $SGPT_WRAPPER — leaving it unchanged."
            echo "==> If you want the managed fallback wrapper, move your custom launcher aside first."
            return 0
        fi
    elif [[ ! -x "$SGPT_REAL_BIN" && -x "$SGPT_WRAPPER" ]]; then
        cp "$SGPT_WRAPPER" "$SGPT_REAL_BIN"
        chmod +x "$SGPT_REAL_BIN"
    fi

    if [[ ! -x "$SGPT_REAL_BIN" ]]; then
        echo "WARNING: ShellGPT launcher not found at $SGPT_WRAPPER; skipping sgpt fallback wrapper."
        return 0
    fi

    cat > "$SGPT_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

real_sgpt="${SGPT_REAL_BIN:-$HOME/.local/bin/sgpt-cli}"
primary_model="${SGPT_PRIMARY_MODEL:-${SHELLGPT_GEMINI_PRIMARY_MODEL:-gemini/gemini-3.1-flash-lite}}"
fallback_model="${SGPT_FALLBACK_MODEL:-${SHELLGPT_GEMINI_FALLBACK_MODEL:-gemini/gemini-2.5-flash}}"

load_env_file() {
    local file="$1"
    [ -r "$file" ] || return 0
    set -a
    # shellcheck source=/dev/null
    source "$file"
    set +a
}

load_env_file "$HOME/.config/ai/api.env"
load_env_file "$HOME/.config/shell_gpt/credentials.env"
load_env_file "$HOME/.bashrc.d/ai-keys.bash"

if [ -z "${GEMINI_API_KEY:-}" ] && [ -z "${GOOGLE_API_KEY:-}" ] && [ -r "$HOME/.config/voice-type/gemini-api-key" ]; then
    export GEMINI_API_KEY="$(tr -d '\r\n' < "$HOME/.config/voice-type/gemini-api-key")"
fi

has_model_arg=false
for arg in "$@"; do
    case "$arg" in
        --model|-m|--model=*)
            has_model_arg=true
            break
            ;;
    esac
done

if "$has_model_arg"; then
    exec "$real_sgpt" "$@"
fi

tmp_err="$(mktemp -t sgpt-fallback.XXXXXX)"
trap 'rm -f "$tmp_err"' EXIT

"$real_sgpt" --model "$primary_model" "$@" 2> >(tee "$tmp_err" >&2)
status=$?

if [ "$status" -eq 0 ]; then
    exit 0
fi

if grep -Eiq '503|UNAVAILABLE|ServiceUnavailableError|APIConnectionError|ConnectError|name resolution|high demand|rate.?limit|overload|temporar(y|ily unavailable)' "$tmp_err"; then
    printf '\nsgpt: primary model failed, retrying with fallback: %s\n' "$fallback_model" >&2
    "$real_sgpt" --model "$fallback_model" "$@"
    fallback_status=$?

    if [ "$fallback_status" -ne 0 ]; then
        cat >&2 <<MSG

sgpt: nie udalo sie polaczyc z AI.
Sprawdz internet, klucz/API i dostepnosc modeli.
Model glowny: $primary_model
Fallback: $fallback_model
MSG
    fi

    exit "$fallback_status"
fi

cat >&2 <<'MSG'

sgpt: zapytanie do AI nie powiodlo sie.
To nie wyglada na chwilowe przeciazenie modelu, wiec fallback nie zostal uruchomiony.
Sprawdz komunikat bledu powyzej.
MSG

exit "$status"
EOF
    chmod +x "$SGPT_WRAPPER"
    echo "ShellGPT fallback wrapper installed to $SGPT_WRAPPER"
}

install_sgpt_wrapper

mkdir -p "$BASHRC_D"
chmod 700 "$BASHRC_D"
cat > "$ENV_LOADER" <<'EOF'
# ShellGPT Gemini provider env.
# Reads the same private Gemini key used by voice typing. The sgpt executable
# wrapper handles fallback when the preview model is overloaded.
if [ -z "${GEMINI_API_KEY:-}" ] && [ -r "$HOME/.config/voice-type/gemini-api-key" ]; then
    export GEMINI_API_KEY="$(tr -d '\r\n' < "$HOME/.config/voice-type/gemini-api-key")"
fi

export SHELLGPT_GEMINI_PRIMARY_MODEL="${SHELLGPT_GEMINI_PRIMARY_MODEL:-gemini/gemini-3.1-flash-lite}"
export SHELLGPT_GEMINI_FALLBACK_MODEL="${SHELLGPT_GEMINI_FALLBACK_MODEL:-gemini/gemini-2.5-flash}"
EOF
chmod 600 "$ENV_LOADER"

if [[ "$SHELLGPT_PLACEHOLDER_CONFIG" == "true" ]]; then
    echo "ShellGPT placeholder config written to $CONFIG_FILE"
else
    echo "ShellGPT config written to $CONFIG_FILE"
fi

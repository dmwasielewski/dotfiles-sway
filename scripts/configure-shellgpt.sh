#!/bin/bash
# configure-shellgpt.sh — non-interactive ShellGPT API configuration
# Secrets are loaded from private files or environment variables, never from git.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shell_gpt"
CONFIG_FILE="$CONFIG_DIR/.sgptrc"
BASHRC_D="$HOME/.bashrc.d"
ENV_LOADER="$BASHRC_D/shellgpt-gemini.bash"
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
API_KEY="$OPENAI_STYLE_API_KEY"
SHELLGPT_PLACEHOLDER_CONFIG=false

if [[ "$PROVIDER" == "gemini" || ( "$PROVIDER" == "auto" && -n "$GEMINI_API_KEY" ) ]]; then
    if [[ -z "$GEMINI_API_KEY" ]]; then
        API_KEY="$PLACEHOLDER_KEY"
        SHELLGPT_PLACEHOLDER_CONFIG=true
        echo "SHELLGPT_PROVIDER=gemini but no Gemini API key source was found."
    else
        API_KEY="litellm-provider-env"
        DEFAULT_MODEL_FALLBACK="gemini/gemini-2.5-flash-lite"
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

mkdir -p "$BASHRC_D"
chmod 700 "$BASHRC_D"
cat > "$ENV_LOADER" <<'EOF'
# ShellGPT Gemini provider env.
# Reads the same private Gemini key used by voice typing.
if [ -z "${GEMINI_API_KEY:-}" ] && [ -r "$HOME/.config/voice-type/gemini-api-key" ]; then
    export GEMINI_API_KEY="$(tr -d '\r\n' < "$HOME/.config/voice-type/gemini-api-key")"
fi
EOF
chmod 600 "$ENV_LOADER"

if [[ "$SHELLGPT_PLACEHOLDER_CONFIG" == "true" ]]; then
    echo "ShellGPT placeholder config written to $CONFIG_FILE"
else
    echo "ShellGPT config written to $CONFIG_FILE"
fi

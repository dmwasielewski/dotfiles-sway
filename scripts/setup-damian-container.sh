#!/bin/bash
# setup-damian-container.sh — versioned Fedora toolbox: node, npm, gh, Claude Code, Codex CLI, DeepSeek TUI, ShellGPT + plugins
# Run after first reboot: bash ~/dotfiles-sway/scripts/setup-damian-container.sh

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-damian-container.sh"

HOST_FEDORA_VERSION="$(. /etc/os-release && printf '%s' "${VERSION_ID:-44}")"
TOOLBOX_VERSION="${TOOLBOX_VERSION:-$HOST_FEDORA_VERSION}"
CONTAINER="${TOOLBOX_CONTAINER:-damianf}"
TOOLBOX_IMAGE="${TOOLBOX_IMAGE:-registry.fedoraproject.org/fedora-toolbox:${TOOLBOX_VERSION}}"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Toolbox '$CONTAINER' — setup           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Create toolbox if missing ────────────────────────────────────────────
if toolbox list 2>/dev/null | grep -qw "$CONTAINER"; then
    echo -e "${YELLOW}==> Toolbox '$CONTAINER' already exists — skipping.${NC}"
    step_done "TOOLBOX_CREATED"
else
    run_step "TOOLBOX_CREATED" "Creating toolbox '$CONTAINER'" \
        toolbox create --assumeyes --image "$TOOLBOX_IMAGE" "$CONTAINER"
fi

# ── Install packages ─────────────────────────────────────────────────────
run_step "TOOLBOX_PACKAGES" "Installing node, npm, gh, git, pip inside toolbox" \
    toolbox run --container "$CONTAINER" sudo dnf install -y nodejs npm gh git python3-pip

run_step "TOOLBOX_TERMINAL_TOOLS" "Installing terminal inspection/search tools inside toolbox" \
    toolbox run --container "$CONTAINER" sudo dnf install -y btop duf bat ncdu ripgrep fzf fd-find

# ── Dev language toolchains (Go, Rust, Python tooling) ────────────────────
# Languages live in the container, never on the immutable host. Cargo/pipx
# install into the shared $HOME, so the binaries are visible from the host too.
run_step "TOOLBOX_GO" "Installing Go toolchain" \
    toolbox run --container "$CONTAINER" sudo dnf install -y golang

run_step "TOOLBOX_PYTHON_TOOLING" "Installing Python tooling (pipx + uv)" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        sudo dnf install -y pipx
        pipx ensurepath >/dev/null 2>&1 || true
        pipx install uv >/dev/null 2>&1 || pipx upgrade uv >/dev/null 2>&1 || true
    '

run_step "TOOLBOX_RUST" "Installing Rust toolchain (rustup + rust-analyzer)" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        sudo dnf install -y curl
        if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
            curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        fi
        "$HOME/.cargo/bin/rustup" component add rust-analyzer
    '

# ── Configure npm prefix ─────────────────────────────────────────────────
run_step "TOOLBOX_NPM_PREFIX" "Configuring npm prefix (~/.npm-global)" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        mkdir -p ~/.npm-global
        touch ~/.npmrc
        sed -i "/^prefix=/d" ~/.npmrc
        printf "prefix=%s\n" "$HOME/.npm-global" >> ~/.npmrc
        grep -q "npm-global" ~/.bashrc || echo "export PATH=\$PATH:~/.npm-global/bin" >> ~/.bashrc
    '

# ── Install AI coding CLIs ───────────────────────────────────────────────
run_step "AI_CLI_TOOLS_INSTALLED" "Installing Claude Code, OpenAI Codex CLI, DeepSeek TUI, and markdownlint-cli2" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        PATH="$HOME/.npm-global/bin:$PATH" npm install -g @anthropic-ai/claude-code @openai/codex deepseek-tui markdownlint-cli2
    '
step_done "CLAUDE_CODE_INSTALLED"
step_done "CODEX_CLI_INSTALLED"
step_done "DEEPSEEK_TUI_INSTALLED"

run_step "DEEPSEEK_TUI_WRAPPER" "Installing DeepSeek TUI low-motion wrapper" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        mkdir -p ~/.local/bin ~/.npm-global/bin
        ln -sf "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh" ~/.local/bin/deepseek
        ln -sf "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh" ~/.local/bin/deepseek-tui
        ln -sf "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh" ~/.npm-global/bin/deepseek
        ln -sf "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh" ~/.npm-global/bin/deepseek-tui
        chmod +x "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh"
        grep -q ".local/bin" ~/.bashrc || echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
    '

# ── Install and configure ShellGPT ───────────────────────────────────────
run_step "SHELLGPT_INSTALLED" "Installing ShellGPT CLI (sgpt)" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        pip3 install "shell-gpt[litellm]" --user --upgrade --quiet
        grep -q ".local/bin" ~/.bashrc || echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.bashrc
    '

echo -e "\n${CYAN}==> Configuring ShellGPT from private API sources...${NC}"
if toolbox run --container "$CONTAINER" bash "$DOTFILES/scripts/configure-shellgpt.sh"; then
    if toolbox run --container "$CONTAINER" grep -q '^OPENAI_API_KEY=missing-shellgpt-api-key$' "$HOME/.config/shell_gpt/.sgptrc"; then
        step_skip "SHELLGPT_CONFIGURED"
        echo -e "${YELLOW}⚠ ShellGPT has a non-interactive placeholder config; provide a private API key source for real API use${NC}"
    elif toolbox run --container "$CONTAINER" test -s "$HOME/.config/shell_gpt/.sgptrc"; then
        step_done "SHELLGPT_CONFIGURED"
        echo -e "${GREEN}✓ ShellGPT API config present${NC}"
    else
        step_skip "SHELLGPT_CONFIGURED"
        echo -e "${YELLOW}⚠ ShellGPT installed, but no private API key source was found${NC}"
    fi
else
    step_failed "SHELLGPT_CONFIGURED"
    echo -e "${YELLOW}⚠ ShellGPT installed, but API config failed${NC}"
fi

# ── Install Claude Code plugins ──────────────────────────────────────────
echo -e "\n${CYAN}==> Installing Claude Code plugins...${NC}"
toolbox run --container "$CONTAINER" bash -c '
    set -eo pipefail
    PATH="$HOME/.npm-global/bin:$PATH"
    claude plugin install superpowers@claude-plugins-official --yes 2>/dev/null || true
    claude plugin install code-simplifier@claude-plugins-official --yes 2>/dev/null || true
    claude plugin install context7@claude-plugins-official --yes 2>/dev/null || true
' && step_done "CLAUDE_PLUGINS_INSTALLED" \
  || { step_failed "CLAUDE_PLUGINS_INSTALLED"
       echo -e "${YELLOW}⚠ Plugins: install manually after entering the container:${NC}"
       echo -e "  toolbox enter $CONTAINER"
       echo -e "  claude plugin install superpowers@claude-plugins-official --yes"
     }

# ── Voice typing — faster-whisper + google-genai ────────────────────────
run_step "VOICE_WHISPER" "Installing faster-whisper + google-genai (voice typing)" \
    toolbox run --container "$CONTAINER" bash -c '
        set -eo pipefail
        pip3 install faster-whisper google-genai --user --quiet
        # Pre-download the small model once to avoid delay on first use.
        if [ ! -d "$HOME/.cache/huggingface/hub" ] || ! find "$HOME/.cache/huggingface/hub" -maxdepth 1 -type d -name "*Systran*faster-whisper-small*" | grep -q .; then
            python3 -c "from faster_whisper import WhisperModel; WhisperModel(\"small\", device=\"cpu\", compute_type=\"int8\")"
        else
            echo "faster-whisper small model already cached — skipping download"
        fi
        grep -q ".local/bin" ~/.bashrc || echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.bashrc
    '

# ── Verify ───────────────────────────────────────────────────────────────
echo -e "\n${CYAN}==> Verifying toolbox '$CONTAINER'...${NC}"
VERIFY_FAIL=0
for tool in node npm gh claude codex deepseek sgpt git btop duf bat ncdu rg fzf fd go cargo rustc rust-analyzer uv; do
    if toolbox run --container "$CONTAINER" which "$tool" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $tool"
    else
        echo -e "  ${RED}✗${NC} $tool — MISSING"
        ((VERIFY_FAIL++))
    fi
done

if [[ $VERIFY_FAIL -eq 0 ]]; then
    step_done "DAMIAN_CONTAINER_READY"
else
    step_failed "DAMIAN_CONTAINER_READY"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Toolbox '$CONTAINER' ready!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " Fedora version:   ${CYAN}${TOOLBOX_VERSION}${NC}"
echo -e " Enter container:  ${CYAN}toolbox enter $CONTAINER${NC}"
echo -e " Run Claude Code:  ${CYAN}claude${NC}"
echo -e " Run Codex CLI:    ${CYAN}codex${NC}"
echo -e " Run ShellGPT:     ${CYAN}sgpt${NC}"
echo ""
echo -e " ${YELLOW}Post-setup notes:${NC}"
echo ""
echo -e "  1. Gemini API key for English voice correction:
     ${CYAN}mkdir -p ~/.config/voice-type${NC}
     ${CYAN}echo \"YOUR_KEY\" > ~/.config/voice-type/gemini-api-key && chmod 600 ~/.config/voice-type/gemini-api-key${NC}
     Get free key: https://aistudio.google.com

  2. Set your Anthropic API key in a private file:"
echo -e "     ${CYAN}mkdir -p ~/.bashrc.d && chmod 700 ~/.bashrc.d${NC}"
echo -e "     ${CYAN}echo 'export ANTHROPIC_API_KEY=\"your-key\"' > ~/.bashrc.d/ai-keys.bash && chmod 600 ~/.bashrc.d/ai-keys.bash${NC}"
echo -e "     Get key: https://console.anthropic.com/settings/keys"
echo ""
echo -e "  3. ShellGPT config is automatic when one of these private sources exists:"
echo -e "     ${CYAN}~/.config/voice-type/gemini-api-key${NC} (preferred, shared with voice typing),"
echo -e "     ${CYAN}GEMINI_API_KEY${NC}, ${CYAN}GOOGLE_API_KEY${NC}, ${CYAN}OPENAI_API_KEY${NC}, ${CYAN}SHELLGPT_API_KEY${NC},"
echo -e "     ${CYAN}~/.config/ai/api.env${NC}, ${CYAN}~/.config/shell_gpt/credentials.env${NC}, or ${CYAN}~/.bashrc.d/ai-keys.bash${NC}"
echo ""
echo -e "  4. Log in to Claude Code:"
echo -e "     ${CYAN}toolbox enter $CONTAINER${NC}  →  ${CYAN}claude login${NC}"
echo ""
echo -e "  5. Log in to GitHub CLI:"
echo -e "     ${CYAN}toolbox enter $CONTAINER${NC}  →  ${CYAN}gh auth login${NC}"
echo ""
echo -e "  6. Log in to Codex CLI:"
echo -e "     ${CYAN}toolbox enter $CONTAINER${NC}  →  ${CYAN}codex login${NC}"
echo ""
print_state_summary

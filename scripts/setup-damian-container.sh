#!/bin/bash
# setup-damian-container.sh — Fedora 43 toolbox: node, npm, gh, Claude Code + plugins
# Run after first reboot: bash ~/dotfiles-sway/scripts/setup-damian-container.sh

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"

CONTAINER="damian"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Toolbox 'damian' — setup               ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Create toolbox if missing ────────────────────────────────────────────
if toolbox list 2>/dev/null | grep -qw "$CONTAINER"; then
    echo -e "${YELLOW}==> Toolbox '$CONTAINER' already exists — skipping.${NC}"
    step_done "TOOLBOX_CREATED"
else
    run_step "TOOLBOX_CREATED" "Creating toolbox '$CONTAINER'" \
        toolbox create --image registry.fedoraproject.org/fedora-toolbox:43 "$CONTAINER"
fi

# ── Install packages ─────────────────────────────────────────────────────
run_step "TOOLBOX_PACKAGES" "Installing node, npm, gh, git inside toolbox" \
    toolbox run --container "$CONTAINER" sudo dnf install -y nodejs npm gh git

# ── Configure npm prefix ─────────────────────────────────────────────────
run_step "TOOLBOX_NPM_PREFIX" "Configuring npm prefix (~/.npm-global)" \
    toolbox run --container "$CONTAINER" bash -c '
        mkdir -p ~/.npm-global
        npm config set prefix ~/.npm-global
        grep -q "npm-global" ~/.bashrc || echo "export PATH=\$PATH:~/.npm-global/bin" >> ~/.bashrc
    '

# ── Install Claude Code ──────────────────────────────────────────────────
run_step "CLAUDE_CODE_INSTALLED" "Installing Claude Code" \
    toolbox run --container "$CONTAINER" bash -c '
        source ~/.bashrc
        PATH=$PATH:~/.npm-global/bin npm install -g @anthropic-ai/claude-code
    '

# ── Install Claude Code plugins ──────────────────────────────────────────
echo -e "\n${CYAN}==> Installing Claude Code plugins...${NC}"
toolbox run --container "$CONTAINER" bash -c '
    source ~/.bashrc
    PATH=$PATH:~/.npm-global/bin
    claude plugin install superpowers@claude-plugins-official --yes 2>/dev/null || true
    claude plugin install code-simplifier@claude-plugins-official --yes 2>/dev/null || true
    claude plugin install context7@claude-plugins-official --yes 2>/dev/null || true
' && step_done "CLAUDE_PLUGINS_INSTALLED" \
  || { step_failed "CLAUDE_PLUGINS_INSTALLED"
       echo -e "${YELLOW}⚠ Plugins: install manually after entering the container:${NC}"
       echo -e "  toolbox enter damian"
       echo -e "  claude plugin install superpowers@claude-plugins-official --yes"
     }

# ── Voice typing — faster-whisper ───────────────────────────────────────
run_step "VOICE_WHISPER" "Installing faster-whisper (local AI speech recognition)" \
    toolbox run --container "$CONTAINER" bash -c '
        pip3 install faster-whisper --user --quiet
        # Pre-download the small model (~470 MB) to avoid delay on first use
        python3 -c "from faster_whisper import WhisperModel; WhisperModel(\"small\", device=\"cpu\", compute_type=\"int8\")"
        grep -q ".local/bin" ~/.bashrc || echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.bashrc
    '

# ── Verify ───────────────────────────────────────────────────────────────
echo -e "\n${CYAN}==> Verifying toolbox 'damian'...${NC}"
VERIFY_FAIL=0
for tool in node npm gh claude git; do
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
echo -e "${BOLD} Toolbox 'damian' ready!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " Enter container:  ${CYAN}toolbox enter damian${NC}"
echo -e " Run Claude Code:  ${CYAN}claude${NC}"
echo ""
echo -e " ${YELLOW}Manual steps required:${NC}"
echo ""
echo -e "  1. Set your API key (inside damian container):"
echo -e "     ${CYAN}echo 'export ANTHROPIC_API_KEY=\"your-key\"' >> ~/.bashrc${NC}"
echo -e "     Get key: https://console.anthropic.com/settings/keys"
echo ""
echo -e "  2. Log in to Claude Code:"
echo -e "     ${CYAN}toolbox enter damian${NC}  →  ${CYAN}claude login${NC}"
echo ""
echo -e "  3. Log in to GitHub CLI:"
echo -e "     ${CYAN}toolbox enter damian${NC}  →  ${CYAN}gh auth login${NC}"
echo ""

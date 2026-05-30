#!/bin/bash
# setup-ubuntu-dev-container.sh — Ubuntu 26.04 distrobox with the same AI/dev CLI stack as toolbox 'damianf'
# Run after first reboot: bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-ubuntu-dev-container.sh"

UBUNTU_DEV_VERSION="${UBUNTU_DEV_VERSION:-26.04}"
CONTAINER="${UBUNTU_DEV_CONTAINER:-damianu}"
BASE_IMAGE="${UBUNTU_DEV_IMAGE:-docker.io/library/ubuntu:${UBUNTU_DEV_VERSION}}"
FIXED_IMAGE="localhost/${CONTAINER}:${UBUNTU_DEV_VERSION}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/distrobox"

# Helper: run command inside the Ubuntu dev container
ubox() { distrobox enter --name "$CONTAINER" -- bash -lc "set -euo pipefail; $*"; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Distrobox '$CONTAINER' — Ubuntu dev setup   ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [[ -t 0 ]] || sudo -n -v >/dev/null 2>&1; then
    require_sudo_session
else
    echo -e "${YELLOW}==> No interactive sudo session available on the host — continuing with container-level sudo checks.${NC}"
fi
mkdir -p "$CACHE_DIR"

# ── Build image with apt HTTP pipeline disabled ──────────────────────────
if ! podman image exists "$FIXED_IMAGE" 2>/dev/null; then
    echo -e "${CYAN}==> Building Ubuntu ${UBUNTU_DEV_VERSION} dev image with apt HTTP pipeline disabled...${NC}"
    printf 'FROM %s\nRUN printf "Acquire::http::Pipeline-Depth \\"0\\";\\nAcquire::Retries \\"5\\";\\n" > /etc/apt/apt.conf.d/99-no-pipeline && apt-get update -qq\n' \
        "$BASE_IMAGE" | podman build -t "$FIXED_IMAGE" - 2>&1 | tail -3
    echo -e "${GREEN}✓ Image built${NC}"
fi

# ── Create container if missing ──────────────────────────────────────────
if podman container exists "$CONTAINER" 2>/dev/null; then
    CURRENT_VERSION="$(distrobox enter --name "$CONTAINER" -- bash -lc '. /etc/os-release && printf "%s" "$VERSION_ID"' 2>/dev/null || true)"
    if [[ -z "$CURRENT_VERSION" ]]; then
        echo -e "${YELLOW}==> Existing container '$CONTAINER' is not enterable yet — recreating it automatically.${NC}"
        distrobox stop "$CONTAINER" --yes >/dev/null 2>&1 || true
        distrobox rm "$CONTAINER" --force >/dev/null 2>&1 || true
        run_step "UBUNTU_DEV_CREATED" "Recreating Ubuntu dev container ($CONTAINER, Ubuntu ${UBUNTU_DEV_VERSION})" \
            distrobox create --name "$CONTAINER" --image "$FIXED_IMAGE"
    elif [[ "$CURRENT_VERSION" != "$UBUNTU_DEV_VERSION" ]]; then
        echo -e "${RED}✗ Container '$CONTAINER' exists, but is Ubuntu ${CURRENT_VERSION:-unknown}; expected ${UBUNTU_DEV_VERSION}.${NC}"
        echo -e "${YELLOW}  Recreate it manually if you want to upgrade:${NC}"
        echo -e "${YELLOW}  distrobox stop $CONTAINER --yes && distrobox rm $CONTAINER --force${NC}"
        echo -e "${YELLOW}  bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh${NC}"
        step_failed "UBUNTU_DEV_CREATED"
        exit 1
    fi
    echo -e "${YELLOW}==> Container '$CONTAINER' already exists on Ubuntu ${UBUNTU_DEV_VERSION} — skipping creation.${NC}"
    step_done "UBUNTU_DEV_CREATED"
else
    run_step "UBUNTU_DEV_CREATED" "Creating Ubuntu dev container ($CONTAINER, Ubuntu ${UBUNTU_DEV_VERSION})" \
        distrobox create --name "$CONTAINER" --image "$FIXED_IMAGE"
fi

# ── Base packages ────────────────────────────────────────────────────────
run_step "UBUNTU_DEV_BASE_PKGS" "Installing Ubuntu dev base packages" \
    ubox "sudo apt-get update -qq &&
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            ca-certificates curl gnupg git python3 python3-pip python3-venv \
            build-essential jq xdg-utils ffmpeg"

run_step "UBUNTU_DEV_TERMINAL_TOOLS" "Installing terminal inspection/search tools" \
    ubox "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            btop duf bat ncdu ripgrep fzf fd-find"

# ── Dev language toolchains (parity with toolbox damianf) ─────────────────
# Go is per-OS (apt). Rust (rustup) and uv (via pipx) install into the shared
# $HOME, so they are visible from every container and the host alike.
run_step "UBUNTU_DEV_GO" "Installing Go toolchain" \
    ubox "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go"

run_step "UBUNTU_DEV_PYTHON_TOOLING" "Installing Python tooling (pipx + uv)" \
    ubox "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y pipx &&
        pipx ensurepath >/dev/null 2>&1 || true
        pipx install uv >/dev/null 2>&1 || pipx upgrade uv >/dev/null 2>&1 || true"

run_step "UBUNTU_DEV_RUST" "Installing Rust toolchain (rustup + rust-analyzer)" \
    ubox 'if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
            curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        fi
        "$HOME/.cargo/bin/rustup" component add rust-analyzer'

# ── Node.js 22 + GitHub CLI ──────────────────────────────────────────────
run_step "UBUNTU_DEV_NODEJS" "Installing Node.js 22 and GitHub CLI" \
    ubox "sudo install -m 0755 -d /etc/apt/keyrings &&
        if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
        fi &&
        printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main\n' | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null &&
        sudo apt-get update -qq &&
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs gh"

# ── Configure npm prefix ─────────────────────────────────────────────────
run_step "UBUNTU_DEV_NPM_PREFIX" "Configuring npm prefix (~/.npm-global)" \
    ubox "mkdir -p ~/.npm-global &&
        touch ~/.npmrc &&
        sed -i '/^prefix=/d' ~/.npmrc &&
        printf 'prefix=%s\n' \"\$HOME/.npm-global\" >> ~/.npmrc"

# ── Install AI coding CLIs ───────────────────────────────────────────────
run_step "UBUNTU_DEV_AI_CLI_TOOLS" "Installing Claude Code, OpenAI Codex CLI, DeepSeek TUI, and markdownlint-cli2" \
    ubox "PATH=\"\$HOME/.npm-global/bin:\$PATH\" npm install -g @anthropic-ai/claude-code @openai/codex deepseek-tui markdownlint-cli2"
step_done "UBUNTU_DEV_CLAUDE_CODE_INSTALLED"
step_done "UBUNTU_DEV_CODEX_CLI_INSTALLED"
step_done "UBUNTU_DEV_DEEPSEEK_TUI_INSTALLED"

run_step "UBUNTU_DEV_DEEPSEEK_WRAPPER" "Installing DeepSeek TUI low-motion wrapper" \
    ubox "mkdir -p ~/.local/bin ~/.npm-global/bin &&
        ln -sf \"\$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh\" ~/.local/bin/deepseek &&
        ln -sf \"\$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh\" ~/.local/bin/deepseek-tui &&
        ln -sf \"\$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh\" ~/.npm-global/bin/deepseek &&
        ln -sf \"\$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh\" ~/.npm-global/bin/deepseek-tui &&
        chmod +x \"\$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh\""

# ── Install and configure ShellGPT ───────────────────────────────────────
run_step "UBUNTU_DEV_SHELLGPT_INSTALLED" "Installing ShellGPT CLI (sgpt)" \
    ubox "pip3 install --user --break-system-packages \"shell-gpt[litellm]\" --upgrade --quiet"

echo -e "\n${CYAN}==> Configuring ShellGPT in '$CONTAINER' from private API sources...${NC}"
if distrobox enter --name "$CONTAINER" -- bash "$DOTFILES/scripts/configure-shellgpt.sh"; then
    if distrobox enter --name "$CONTAINER" -- grep -q '^OPENAI_API_KEY=missing-shellgpt-api-key$' "$HOME/.config/shell_gpt/.sgptrc"; then
        step_skip "UBUNTU_DEV_SHELLGPT_CONFIGURED"
        echo -e "${YELLOW}⚠ ShellGPT has a non-interactive placeholder config; provide a private API key source for real API use${NC}"
    elif distrobox enter --name "$CONTAINER" -- test -s "$HOME/.config/shell_gpt/.sgptrc"; then
        step_done "UBUNTU_DEV_SHELLGPT_CONFIGURED"
        echo -e "${GREEN}✓ ShellGPT API config present${NC}"
    else
        step_skip "UBUNTU_DEV_SHELLGPT_CONFIGURED"
        echo -e "${YELLOW}⚠ ShellGPT installed, but no private API key source was found${NC}"
    fi
else
    step_failed "UBUNTU_DEV_SHELLGPT_CONFIGURED"
    echo -e "${YELLOW}⚠ ShellGPT installed, but API config failed${NC}"
fi

# ── Install Claude Code plugins ──────────────────────────────────────────
echo -e "\n${CYAN}==> Installing Claude Code plugins in '$CONTAINER'...${NC}"
if ubox "PATH=\"\$HOME/.npm-global/bin:\$PATH\"
    claude plugin install superpowers@claude-plugins-official --yes 2>/dev/null || true
    claude plugin install code-simplifier@claude-plugins-official --yes 2>/dev/null || true
    claude plugin install context7@claude-plugins-official --yes 2>/dev/null || true"; then
    step_done "UBUNTU_DEV_CLAUDE_PLUGINS_INSTALLED"
else
    step_failed "UBUNTU_DEV_CLAUDE_PLUGINS_INSTALLED"
    echo -e "${YELLOW}⚠ Plugins: install manually after entering the container:${NC}"
    echo -e "  distrobox enter $CONTAINER"
    echo -e "  claude plugin install superpowers@claude-plugins-official --yes"
fi

# ── Voice typing parity tools ────────────────────────────────────────────
run_step "UBUNTU_DEV_VOICE_WHISPER" "Installing faster-whisper + google-genai" \
    ubox "pip3 install --user --break-system-packages faster-whisper google-genai --quiet &&
        if [ ! -d \"\$HOME/.cache/huggingface/hub\" ] || ! find \"\$HOME/.cache/huggingface/hub\" -maxdepth 1 -type d -name '*Systran*faster-whisper-small*' | grep -q .; then
            python3 -c \"from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8')\"
        else
            echo 'faster-whisper small model already cached — skipping download'
        fi"

# ── Verify ───────────────────────────────────────────────────────────────
echo -e "\n${CYAN}==> Verifying distrobox '$CONTAINER'...${NC}"
VERIFY_FAIL=0
for tool in node npm gh claude codex deepseek sgpt git btop duf bat ncdu rg fzf fd go cargo rustc rust-analyzer uv; do
    if distrobox enter --name "$CONTAINER" -- which "$tool" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $tool"
    else
        echo -e "  ${RED}✗${NC} $tool — MISSING"
        ((VERIFY_FAIL++))
    fi
done

if distrobox enter --name "$CONTAINER" -- bash -lc 'PATH="$HOME/.npm-global/bin:$PATH" command -v markdownlint-cli2 >/dev/null 2>&1'; then
    echo -e "  ${GREEN}✓${NC} markdownlint-cli2"
else
    echo -e "  ${RED}✗${NC} markdownlint-cli2 — MISSING"
    ((VERIFY_FAIL++))
fi

if distrobox enter --name "$CONTAINER" -- python3 -c "import faster_whisper" &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} faster-whisper"
else
    echo -e "  ${RED}✗${NC} faster-whisper — MISSING"
    ((VERIFY_FAIL++))
fi

if [[ $VERIFY_FAIL -eq 0 ]]; then
    step_done "UBUNTU_DEV_CONTAINER_READY"
else
    step_failed "UBUNTU_DEV_CONTAINER_READY"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Ubuntu dev container ready!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " Ubuntu version:  ${CYAN}${UBUNTU_DEV_VERSION}${NC}"
echo -e " Container name:  ${CYAN}${CONTAINER}${NC}"
echo -e " Enter container: ${CYAN}distrobox enter ${CONTAINER}${NC}"
echo -e " Run Claude Code: ${CYAN}claude${NC}"
echo -e " Run Codex CLI:   ${CYAN}codex${NC}"
echo -e " Run ShellGPT:    ${CYAN}sgpt${NC}"
echo ""
echo -e " ${YELLOW}Notes:${NC}"
echo -e "  - This Ubuntu distrobox mirrors the main AI/dev CLI stack from toolbox '${CYAN}damianf${NC}'."
echo -e "  - Voice typing still uses toolbox '${CYAN}damianf${NC}' by default through scripts/voice-type-stop.sh."
echo -e "  - Log in manually after entering the container:"
echo -e "      ${CYAN}claude login${NC}"
echo -e "      ${CYAN}gh auth login${NC}"
echo -e "      ${CYAN}codex login${NC}"
echo ""
print_state_summary

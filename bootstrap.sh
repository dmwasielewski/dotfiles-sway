#!/bin/bash
# bootstrap.sh — fresh install entry point
# Usage: bash <(curl -s https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh)
# Prerequisites: SSH key generated and added to GitHub

set -euo pipefail

GITHUB_USER="dmwasielewski"
REPO="dotfiles-sway"
DOTFILES="$HOME/dotfiles-sway"
STATE_FILE="$HOME/.dotfiles-install-state"
LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

setup_logging() {
    export DOTFILES_LOG_FILE="$LOG_FILE"

    if [[ "${DOTFILES_LOG_ACTIVE:-}" == "1" ]]; then
        echo "==> Logging to $LOG_FILE"
        echo "==> Script: bootstrap.sh"
        return
    fi

    export DOTFILES_LOG_ACTIVE=1
    touch "$LOG_FILE"
    exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' | tee -a "$LOG_FILE") 2>&1
    DOTFILES_LOG_PID=$!
    trap 'exec >&- 2>&-; wait "$DOTFILES_LOG_PID" 2>/dev/null || true' EXIT

    echo "==> Logging to $LOG_FILE"
    echo "==> Script: bootstrap.sh"
}

setup_logging

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   dotfiles-sway — bootstrap              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

touch "$STATE_FILE"

step_save() {
    local key="$1" status="$2"
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${status}|" "$STATE_FILE"
    else
        echo "${key}=${status}" >> "$STATE_FILE"
    fi
}

run_step() {
    local key="$1" label="$2"
    shift 2
    echo -e "${CYAN}==> ${label}...${NC}"
    if "$@"; then
        step_save "$key" "done"
        echo -e "${GREEN}✓ ${label}${NC}\n"
    else
        step_save "$key" "failed"
        echo -e "${RED}✗ FAILED: ${label}${NC}"
        echo ""
        echo "Install state:"
        grep -E "^[A-Z]" "$STATE_FILE" | while IFS='=' read -r k v; do
            [[ "$v" == "done" ]]   && echo -e "  ${GREEN}✓${NC} $k"
            [[ "$v" == "failed" ]] && echo -e "  ${RED}✗${NC} $k"
        done
        echo ""
        echo -e "${YELLOW}Fix the issue and re-run: bash ~/dotfiles-sway/bootstrap.sh${NC}"
        exit 1
    fi
}

# ── Step 1: Clone repository ─────────────────────────────────────────────
if [[ -d "$DOTFILES/.git" ]]; then
    echo -e "${YELLOW}==> $DOTFILES already exists — skipping clone.${NC}"
    step_save "CLONE_REPO" "done"
else
    run_step "CLONE_REPO" "Cloning repository" \
        git clone "git@github.com:$GITHUB_USER/$REPO.git" "$DOTFILES"
fi

# ── Step 2: Symlinks, Flatpaks, toolbox, fonts ───────────────────────────
run_step "SETUP_SYMLINKS" "Running setup (symlinks, Flatpaks, toolbox, fonts)" \
    bash "$DOTFILES/setup.sh"

# ── Step 3: System packages via rpm-ostree ───────────────────────────────
run_step "PACKAGES_LAYERED" "Installing system packages (rpm-ostree — reboot required after)" \
    bash "$DOTFILES/packages.sh"

step_save "REBOOT_DONE" "pending"

# ── Phase 1 summary ──────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Phase 1 complete — reboot required!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " ${YELLOW}After reboot, run in this order:${NC}"
echo ""
echo -e "  1. ${CYAN}bash ~/dotfiles-sway/scripts/check-hardware.sh${NC}"
echo -e "     Verify GPU, VA-API, KVM support"
echo ""
echo -e "  2. ${CYAN}bash ~/dotfiles-sway/scripts/setup-kvm.sh${NC}"
echo -e "     Enable KVM/libvirtd — then log out and back in"
echo ""
echo -e "  3. ${CYAN}bash ~/dotfiles-sway/scripts/setup-damian-container.sh${NC}"
echo -e "     Toolbox damian: node, npm, gh, Claude Code + plugins"
echo ""
echo -e "  4. ${CYAN}bash ~/dotfiles-sway/scripts/setup-security-container.sh${NC}"
echo -e "     Distrobox security: nmap, metasploit, hydra, ..."
echo ""
echo -e "  5. ${CYAN}bash ~/dotfiles-sway/scripts/verify.sh${NC}"
echo -e "     Full verification — checks every component"
echo ""
echo -e " ${BOLD}Reboot now:${NC}  ${CYAN}systemctl reboot${NC}"
echo ""

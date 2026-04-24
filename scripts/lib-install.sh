#!/bin/bash
# lib-install.sh — shared helpers for all install scripts

STATE_FILE="$HOME/.dotfiles-install-state"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step_save() {
    local key="$1" status="$2"
    touch "$STATE_FILE"
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${status}|" "$STATE_FILE"
    else
        echo "${key}=${status}" >> "$STATE_FILE"
    fi
}

step_get()    { grep "^${1}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo ""; }
step_done()   { step_save "$1" "done"; }
step_failed() { step_save "$1" "failed"; }
step_skip()   { step_save "$1" "skipped"; }

# Run a command, save state, exit on failure
run_step() {
    local key="$1" label="$2"
    shift 2
    echo -e "\n${CYAN}==> ${label}...${NC}"
    if "$@"; then
        step_done "$key"
        echo -e "${GREEN}✓ ${label}${NC}"
    else
        step_failed "$key"
        echo -e "${RED}✗ FAILED: ${label}${NC}"
        echo -e "${YELLOW}  Fix the issue and re-run this script.${NC}"
        echo -e "${YELLOW}  State saved to: $STATE_FILE${NC}"
        echo -e "${YELLOW}  Check progress: bash ~/dotfiles-sway/scripts/verify.sh${NC}"
        exit 1
    fi
}

# Run a command, save state, warn on failure (don't exit)
run_step_warn() {
    local key="$1" label="$2"
    shift 2
    echo -e "\n${CYAN}==> ${label}...${NC}"
    if "$@"; then
        step_done "$key"
        echo -e "${GREEN}✓ ${label}${NC}"
    else
        step_failed "$key"
        echo -e "${YELLOW}⚠ WARNING: ${label} — continuing anyway${NC}"
    fi
}

print_state() {
    if [[ -f "$STATE_FILE" ]]; then
        echo -e "\n${BOLD}Install state ($STATE_FILE):${NC}"
        while IFS='=' read -r key val; do
            case "$val" in
                done)    echo -e "  ${GREEN}✓${NC} $key" ;;
                failed)  echo -e "  ${RED}✗${NC} $key" ;;
                skipped) echo -e "  ${YELLOW}⚠${NC} $key (skipped)" ;;
                pending) echo -e "  ${YELLOW}…${NC} $key (pending)" ;;
                *)       echo -e "  ? $key=$val" ;;
            esac
        done < "$STATE_FILE"
    fi
}

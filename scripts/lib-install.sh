#!/bin/bash
# lib-install.sh — shared helpers for all install scripts

STATE_FILE="$HOME/.dotfiles-install-state"
LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

declare -a DOTFILES_EXIT_HOOKS=()

run_exit_hooks() {
    local idx
    for ((idx=${#DOTFILES_EXIT_HOOKS[@]}-1; idx>=0; idx--)); do
        eval "${DOTFILES_EXIT_HOOKS[$idx]}"
    done
}

add_exit_hook() {
    DOTFILES_EXIT_HOOKS+=("$1")
    trap run_exit_hooks EXIT
}

setup_logging() {
    local script_name="${1:-unknown}"
    export DOTFILES_LOG_FILE="$LOG_FILE"

    if [[ "${DOTFILES_LOG_ACTIVE:-}" == "1" ]]; then
        echo "==> Logging to $LOG_FILE"
        echo "==> Script: $script_name"
        return
    fi

    export DOTFILES_LOG_ACTIVE=1
    touch "$LOG_FILE"
    exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' | tee -a "$LOG_FILE") 2>&1
    DOTFILES_LOG_PID=$!
    add_exit_hook 'exec >&- 2>&-; wait "$DOTFILES_LOG_PID" 2>/dev/null || true'

    echo "==> Logging to $LOG_FILE"
    echo "==> Script: $script_name"
}

require_sudo_session() {
    local parent_pid

    if [[ -n "${DOTFILES_SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null; then
        return 0
    fi

    echo "==> Acquiring sudo session for unattended install steps..."
    sudo -v

    parent_pid="$$"
    (
        while true; do
            sleep 20
            if ! sudo -n -v >/dev/null 2>&1; then
                echo "ERROR: sudo session expired during installation." >&2
                kill -TERM "$parent_pid" 2>/dev/null || true
                exit 1
            fi
        done
    ) &
    DOTFILES_SUDO_KEEPALIVE_PID=$!
    add_exit_hook 'if [[ -n "${DOTFILES_SUDO_KEEPALIVE_PID:-}" ]]; then kill "$DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true; wait "$DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true; fi'
}

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

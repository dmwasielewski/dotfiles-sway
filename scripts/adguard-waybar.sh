#!/bin/bash
set -euo pipefail

action="${1:-status}"

ADGUARD_BIN="${ADGUARD_BIN:-adguard-cli}"

json_escape() {
    sed ':a;N;$!ba;s/\n/\\n/g; s/\\/\\\\/g; s/"/\\"/g'
}

emit() {
    local text="$1"
    local klass="$2"
    local tooltip="$3"
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' \
        "$(printf '%s' "$text" | json_escape)" \
        "$(printf '%s' "$klass" | json_escape)" \
        "$(printf '%s' "$tooltip" | json_escape)"
}

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "AdGuard" "$1"
    fi
}

adguard_cmd() {
    if command -v "$ADGUARD_BIN" >/dev/null 2>&1; then
        "$ADGUARD_BIN" "$@"
    elif [[ -x /opt/adguard-cli/adguard-cli ]]; then
        /opt/adguard-cli/adguard-cli "$@"
    else
        return 127
    fi
}

summarize() {
    printf '%s\n' "$1" | sed '/^$/d' | head -n 8 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/[[:space:]]*$//'
}

read_status() {
    adguard_cmd status 2>&1 || true
}

parse_state() {
    local output="$1"

    if [[ "$output" == *"command not found"* ]] || [[ "$output" == *"No such file or directory"* ]]; then
        printf 'missing'
    elif [[ "$output" == *"is not running"* ]] || [[ "$output" == *"start the proxy server"* ]]; then
        printf 'disabled'
    elif [[ "$output" == *"proxy server is running"* ]] || [[ "$output" == *"Protection is enabled"* ]]; then
        printf 'enabled'
    elif [[ "$output" == *"Disable protection"* ]] || [[ "$output" == *"disabled"* ]] || [[ "$output" == *"stopped"* ]]; then
        printf 'disabled'
    elif [[ "$output" == *"Unable to connect"* ]] || [[ "$output" == *"license"* ]] || [[ "$output" == *"activate"* ]]; then
        printf 'needs-setup'
    else
        printf 'unknown'
    fi
}

status_output="$(read_status)"
state="$(parse_state "$status_output")"
tooltip="$(summarize "$status_output")"

if [[ "$action" == "hint" ]]; then
    case "$state" in
        enabled)
            notify "AdGuard jest wlaczony. Aby wylaczyc: sudo adguard-cli stop"
            ;;
        disabled)
            notify "AdGuard jest wylaczony. Aby wlaczyc: sudo adguard-cli start"
            ;;
        needs-setup)
            notify "AdGuard wymaga aktywacji lub konfiguracji. Uzyj: sudo adguard-cli activate"
            ;;
        missing)
            notify "AdGuard CLI nie jest zainstalowany"
            ;;
        *)
            notify "Sprawdz stan w terminalu: adguard-cli status"
            ;;
    esac
    exit 0
fi

case "$state" in
    enabled)
        emit "AG on" "enabled" "${tooltip:-AdGuard protection is enabled}"
        ;;
    disabled)
        emit "AG off" "disabled" "${tooltip:-AdGuard protection is disabled}"
        ;;
    needs-setup)
        emit "AG SET" "needs-setup" "${tooltip:-AdGuard requires activation or setup}"
        ;;
    missing)
        emit "AG ?" "missing" "AdGuard CLI is not installed"
        ;;
    *)
        emit "AG ?" "unknown" "${tooltip:-AdGuard status is unavailable}"
        ;;
esac

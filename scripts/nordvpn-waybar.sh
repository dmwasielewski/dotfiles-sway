#!/bin/bash
set -euo pipefail

action="${1:-status}"

json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g'
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

if ! command -v nordvpn >/dev/null 2>&1; then
    emit "VPN ?" "missing" "NordVPN CLI is not installed"
    exit 0
fi

status_output="$(nordvpn status 2>/dev/null || true)"
status_line="$(printf '%s\n' "$status_output" | awk -F': ' '/^Status:/ {print $2; exit}')"
summarize() {
    printf '%s\n' "$1" | sed '/^$/d' | head -n 6 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/[[:space:]]*$//'
}

case "${status_line:-}" in
    Connected)
        state="connected"
        text="VPN ON"
        tooltip="$(summarize "$status_output")"
        ;;
    Connecting)
        state="connecting"
        text="VPN ..."
        tooltip="$(summarize "$status_output")"
        ;;
    Disconnected|"")
        state="disconnected"
        text="VPN OFF"
        tooltip="$(summarize "$status_output")"
        if [[ -z "$tooltip" ]]; then
            tooltip="NordVPN is disconnected"
        fi
        ;;
    *)
        state="unknown"
        text="VPN ?"
        tooltip="$(summarize "$status_output")"
        if [[ -z "$tooltip" ]]; then
            tooltip="NordVPN status is unavailable"
        fi
        ;;
esac

if [[ "$action" == "toggle" ]]; then
    if [[ "$state" == "connected" ]]; then
        nordvpn disconnect >/dev/null 2>&1 || true
    else
        nordvpn connect >/dev/null 2>&1 || true
    fi
    exit 0
fi

emit "$text" "$state" "$tooltip"

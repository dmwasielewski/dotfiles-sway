#!/bin/bash
# Waybar update indicator — polls cache, refreshes every hour via self-caching
# JSON output: shows update count when >0, empty text hides module when up-to-date
set -euo pipefail

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"
CACHE_MAX_AGE=3600  # refresh every hour

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
        "$(printf '%s' "$3" | json_escape)"
}

emit_cached() {
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
        exit 0
    fi
}

# Serve cache if fresh enough
if [[ -f "$CACHE_FILE" ]]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [[ "$cache_age" -lt "$CACHE_MAX_AGE" ]]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Cache stale or missing — do the slow check
fp_count=0
ostree_count=0
tooltip_parts=()

# Flatpak user updates (fast, ~2-5s)
fp_count=$(flatpak remote-ls --user --updates 2>/dev/null | wc -l)

# rpm-ostree: check staged first (instant, no network)
if rpm-ostree status 2>/dev/null | grep -q "(staged)"; then
    ostree_count=1
    tooltip_parts+=("OS: staged update ready (reboot to apply)")
else
    # No staged update — check remotely (slow ~5-30s)
    check_out=$(rpm-ostree upgrade --check 2>/dev/null || true)
    if printf '%s\n' "$check_out" | grep -q "AvailableUpdate:"; then
        diff_line=$(printf '%s\n' "$check_out" | grep "Diff:" | head -1)
        ostree_count=$(printf '%s\n' "$diff_line" | grep -oP '^\s*Diff:\s*\K[0-9]+' || echo 1)
        tooltip_parts+=("OS: $ostree_count package update(s) available")
    fi
fi

[[ "$fp_count" -gt 0 ]] && tooltip_parts+=("Flatpak: $fp_count update(s)")

total=$(( ostree_count + fp_count ))
tooltip=$(printf '%s\n' "${tooltip_parts[@]+"${tooltip_parts[@]}"}" | tr '\n' ' ' | sed 's/ *$//')

if [[ "$total" -eq 0 ]]; then
    result=$(emit "" "uptodate" "System is up to date")
else
    result=$(emit "⬆ $total" "updates" "${tooltip:-Updates available}")
fi

# Write cache
mkdir -p "$(dirname "$CACHE_FILE")"
printf '%s\n' "$result" > "$CACHE_FILE"
printf '%s\n' "$result"

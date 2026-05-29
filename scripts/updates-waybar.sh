#!/bin/bash
# Waybar update indicator — dynamic detection, no hardcoded names
# Shows breakdown per category: OS | Flatpak | Containers
set -euo pipefail

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_MAX_AGE=3600

json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g'; }

emit() {
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' \
        "$(printf '%s' "$1" | json_escape)" \
        "$(printf '%s' "$2" | json_escape)" \
        "$(printf '%s' "$3" | json_escape)"
}

# Serve cache if still fresh
if [[ -f "$CACHE_FILE" ]]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [[ "$cache_age" -lt "$CACHE_MAX_AGE" ]]; then cat "$CACHE_FILE"; exit 0; fi
fi

total=0
tooltip_parts=()

# ── Flatpak user updates (fast) ───────────────────────────
fp_count=$(flatpak remote-ls --user --updates 2>/dev/null | wc -l)
if [[ "$fp_count" -gt 0 ]]; then
    tooltip_parts+=("Flatpak: $fp_count app(s)")
    total=$(( total + fp_count ))
fi

# ── rpm-ostree ────────────────────────────────────────────
if rpm-ostree status 2>/dev/null | grep -q "(staged)"; then
    tooltip_parts+=("OS: staged — reboot to apply")
    total=$(( total + 1 ))
else
    check_out=$(rpm-ostree upgrade --check 2>&1 || true)
    if printf '%s\n' "$check_out" | grep -q "AvailableUpdate:"; then
        pkg_count=$(printf '%s\n' "$check_out" | grep -oP '^\s*Diff:\s*\K[0-9]+' || echo 1)
        new_ver=$(printf '%s\n' "$check_out" | awk -F": " '/^[[:space:]]*Version:/ {print $2; exit}')
        sec_adv=$(printf '%s\n' "$check_out" | awk -F": " '/SecAdvisories:/ {print $2}')
        tip="OS: $pkg_count pkg(s)"
        [[ -n "$new_ver"  ]] && tip="$tip → $new_ver"
        [[ -n "$sec_adv"  ]] && tip="$tip | ⚠ $sec_adv"
        tooltip_parts+=("$tip")
        total=$(( total + pkg_count ))
    fi
fi

# ── Containers: dynamic discovery, timestamp heuristic ───
# Distrobox containers (lines starting with hex ID)
mapfile -t distrobox_containers < <(
    distrobox list --no-color 2>/dev/null \
    | awk -F'|' '/^[0-9a-f]{12}/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}'
)
# Toolbox containers
mapfile -t toolbox_containers < <(
    toolbox list --containers 2>/dev/null \
    | awk 'NR>1 && NF>=2 {print $2}'
)

container_warn=0
container_lines=()
THRESHOLD_DAYS=7

check_container_age() {
    local name="$1"
    local f="$CACHE_DIR/container-last-update-$name"
    if [[ ! -f "$f" ]]; then
        container_lines+=("$name: never updated")
        container_warn=$(( container_warn + 1 ))
    else
        local age_days=$(( ( $(date +%s) - $(cat "$f") ) / 86400 ))
        container_lines+=("$name: ${age_days}d ago")
        [[ "$age_days" -ge "$THRESHOLD_DAYS" ]] && container_warn=$(( container_warn + 1 ))
    fi
}

for name in "${distrobox_containers[@]+"${distrobox_containers[@]}"}"; do check_container_age "$name"; done
for name in "${toolbox_containers[@]+"${toolbox_containers[@]}"}"; do check_container_age "$name"; done

if [[ "$container_warn" -gt 0 ]]; then
    joined=$(printf '%s | ' "${container_lines[@]}" | sed 's/ | $//')
    tooltip_parts+=("Containers: $joined")
    total=$(( total + container_warn ))
fi

# ── Build output ──────────────────────────────────────────
tooltip=$(printf '%s  ' "${tooltip_parts[@]+"${tooltip_parts[@]}"}" | sed 's/  $//')
[[ "$total" -eq 0 ]] && result=$(emit "" "uptodate" "✔ Everything is up to date") \
                      || result=$(emit "⬆ $total" "updates" "${tooltip:-Updates available}")

mkdir -p "$CACHE_DIR"
printf '%s\n' "$result" > "$CACHE_FILE"
printf '%s\n' "$result"

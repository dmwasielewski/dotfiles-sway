#!/bin/bash
# Waybar update indicator — icon-only, 3 severity classes, multiline tooltip.
# All detection lives in lib-updates.sh (shared with the update menu).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-updates.sh
source "$SCRIPT_DIR/lib-updates.sh"

CACHE_FILE="$CACHE_DIR/waybar-updates.json"
CACHE_MAX_AGE=3600   # serve cached JSON for up to 1h (slow network checks)

json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'; }
emit() {
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' \
        "$(printf '%s' "$1" | json_escape)" \
        "$(printf '%s' "$2" | json_escape)" \
        "$(printf '%s' "$3" | json_escape)"
}

# Serve fresh cache without re-checking
if [[ -f "$CACHE_FILE" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    [[ "$age" -lt "$CACHE_MAX_AGE" ]] && { cat "$CACHE_FILE"; exit 0; }
fi

total=0
os_is_pending=0
lines=()

# ── Flatpak ───────────────────────────────────────────────
fp=$(flatpak_count)
if [[ "$fp" -gt 0 ]]; then
    lines+=("Flatpak: $fp app(s) — updated $(flatpak_last_label)")
    total=$(( total + fp ))
else
    lines+=("Flatpak: up to date")
fi

# ── Fedora OS (check runs once) ───────────────────────────
os_raw="$(os_check_raw)"
if [[ "$(os_staged)" -eq 1 ]]; then
    os_is_pending=1
    lines+=("OS: staged update — reboot to apply")
    total=$(( total + 1 ))
elif [[ "$(os_parse_pending "$os_raw")" -eq 1 ]]; then
    os_is_pending=1
    nv="$(os_parse_version "$os_raw")"; pc="$(os_parse_pkgcount "$os_raw")"
    lines+=("OS: ${pc:-?} pkg(s) → ${nv:-new version}")
    lines+=("  Important: $(os_parse_sec important "$os_raw")  Moderate: $(os_parse_sec moderate "$os_raw")  Low: $(os_parse_sec low "$os_raw")")
    total=$(( total + 1 ))
else
    lines+=("OS: up to date (booted $(os_last_label))")
fi

# ── Containers (dynamic) ──────────────────────────────────
container_lines=()
container_warn=0
add_container() {
    local name="$1" label; label="$(upd_age_label "container-$1")"
    if container_is_stale "$name"; then
        container_lines+=("  $name: $label ⚠"); container_warn=$(( container_warn + 1 ))
    else
        container_lines+=("  $name: $label")
    fi
}
while IFS= read -r c; do [[ -n "$c" ]] && add_container "$c"; done < <(discover_distrobox)
while IFS= read -r c; do [[ -n "$c" ]] && add_container "$c"; done < <(discover_toolbox)

if [[ "${#container_lines[@]}" -gt 0 ]]; then
    lines+=("Containers:")
    for cl in "${container_lines[@]}"; do lines+=("$cl"); done
    total=$(( total + container_warn ))
fi

# ── Severity class ────────────────────────────────────────
if   [[ "$total" -eq 0 ]];      then klass="uptodate"
elif [[ "$os_is_pending" -eq 1 ]]; then klass="critical"
else                                klass="warning"
fi

tooltip="$(printf '%s\n' "${lines[@]}")"
if [[ "$total" -eq 0 ]]; then
    result="$(emit "" "uptodate" "✔ Everything is up to date")"
else
    result="$(emit "⬆" "$klass" "$tooltip")"
fi

mkdir -p "$CACHE_DIR"
printf '%s\n' "$result" > "$CACHE_FILE"
printf '%s\n' "$result"

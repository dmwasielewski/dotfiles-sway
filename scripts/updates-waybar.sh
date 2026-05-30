#!/bin/bash
# Waybar update indicator — icon-only, 3 severity classes, multiline tooltip.
# All detection lives in lib-updates.sh (shared with the update menu).
#
# Two modes:
#   (default)   what Waybar runs every few seconds — ALWAYS instant: it just
#               prints the cached JSON and, if the cache is stale/missing, kicks
#               off a detached background refresh. Never blocks Waybar on the
#               slow (~10s) rpm-ostree check.
#   --compute   the heavy worker: runs all checks and writes the cache. Invoked
#               in the background by the default mode and by the update menu.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-updates.sh
source "$SCRIPT_DIR/lib-updates.sh"

CACHE_FILE="$CACHE_DIR/waybar-updates.json"
CACHE_MAX_AGE=900    # background-refresh the cache when older than 15 min

json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'; }
emit() {
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' \
        "$(printf '%s' "$1" | json_escape)" \
        "$(printf '%s' "$2" | json_escape)" \
        "$(printf '%s' "$3" | json_escape)"
}

# ── Heavy worker: compute everything and write the cache atomically ────────
compute_and_cache() {
    local total=0 os_is_pending=0 sec_high=0
    local lines=()

    # Flatpak (first — most frequently updated)
    local fp; fp=$(flatpak_count)
    if [[ "$fp" -gt 0 ]]; then
        lines+=("Flatpak: $fp app(s) — last updated $(flatpak_last_label)")
        total=$(( total + fp ))
    else
        lines+=("Flatpak: up to date — last updated $(flatpak_last_label)")
    fi

    # Containers (second)
    local container_lines=() container_warn=0 c
    add_container() {
        local name="$1" label; label="$(container_age_label "$1")"
        if container_is_stale "$name"; then
            container_lines+=("  $name: $label ⚠"); container_warn=$(( container_warn + 1 ))
        else
            container_lines+=("  $name: $label")
        fi
    }
    while IFS= read -r c <&3; do [[ -n "$c" ]] && add_container "$c"; done 3< <(discover_distrobox)
    while IFS= read -r c <&3; do [[ -n "$c" ]] && add_container "$c"; done 3< <(discover_toolbox)
    if [[ "${#container_lines[@]}" -gt 0 ]]; then
        lines+=("Containers:")
        for c in "${container_lines[@]}"; do lines+=("$c"); done
        total=$(( total + container_warn ))
    fi

    # Fedora OS (last-known-good cache; stale fallback when repo offline)
    local os_fresh os_raw os_state stale_note=""
    os_fresh="$(os_refresh_cache)"
    os_raw="$(os_cached_raw)"
    os_state="$(os_parse_state "$os_raw")"
    [[ "$os_fresh" == "stale" ]] && stale_note=" (as of $(os_cache_date), repo offline)"

    if [[ "$(os_staged)" -eq 1 ]]; then
        os_is_pending=1; lines+=("OS: staged update — reboot to apply"); total=$(( total + 1 ))
    elif [[ "$os_fresh" == "none" ]]; then
        lines+=("OS: not yet checked (repo unreachable)")
    elif [[ "$os_state" == "pending" ]]; then
        os_is_pending=1
        local nv pc reg
        nv="$(os_parse_version "$os_raw")"; pc="$(os_parse_pkgcount "$os_raw")"
        sec_high="$(os_parse_sec_total "$os_raw")"
        reg=$(( ${pc:-0} - sec_high )); [[ "$reg" -lt 0 ]] && reg=0
        lines+=("OS: ${pc:-?} packages → ${nv:-new version}$stale_note")
        lines+=("  Security: $sec_high")
        lines+=("  Regular:  $reg")
        total=$(( total + 1 ))
    else
        lines+=("OS: up to date (booted $(os_last_label))$stale_note")
    fi

    # Severity class
    local klass
    if   [[ "$total" -eq 0 ]];                              then klass="uptodate"
    elif [[ "$os_is_pending" -eq 1 || "$sec_high" -gt 0 ]]; then klass="critical"
    else                                                         klass="warning"; fi

    local tooltip result
    tooltip="$(printf '%s\n' "${lines[@]}")"
    result="$(emit "⬆" "$klass" "$tooltip")"

    # Write atomically so Waybar never reads a half-written file.
    mkdir -p "$CACHE_DIR"
    printf '%s\n' "$result" > "$CACHE_FILE.tmp" && mv -f "$CACHE_FILE.tmp" "$CACHE_FILE"
    printf '%s\n' "$result"
}

# Spawn the heavy worker fully detached so Waybar doesn't wait on it.
spawn_refresh() {
    setsid -f "$SCRIPT_DIR/updates-waybar.sh" --compute >/dev/null 2>&1 || \
        ( "$SCRIPT_DIR/updates-waybar.sh" --compute >/dev/null 2>&1 & )
}

# ── Mode dispatch ─────────────────────────────────────────────────────────
if [[ "${1:-}" == "--compute" ]]; then
    compute_and_cache >/dev/null
    exit 0
fi

# Default (Waybar) mode — always instant.
if [[ -f "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    [[ "$age" -ge "$CACHE_MAX_AGE" ]] && spawn_refresh   # stale → refresh in background
    exit 0
fi

# No cache yet — show a neutral placeholder instantly and compute in background.
emit "⬆" "uptodate" "Checking for updates…"
spawn_refresh

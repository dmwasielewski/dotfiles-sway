#!/bin/bash
# lib-updates.sh — shared update-detection logic for Waybar indicator and menu.
# Single source of truth so the indicator count and the menu list always agree.
# No hardcoded names: containers, apps and OS state are all discovered at runtime.
#
# Source this file; do not execute it directly.

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CONTAINER_STALE_DAYS="${CONTAINER_STALE_DAYS:-7}"

# ── Timestamp helpers (our record of when we last ran an update) ──────────
upd_ts_file()   { printf '%s/update-last-%s' "$CACHE_DIR" "$1"; }
upd_record()    { mkdir -p "$CACHE_DIR"; date +%s > "$(upd_ts_file "$1")"; }
upd_age_days()  {                      # echoes integer days, -1 if never
    local f; f="$(upd_ts_file "$1")"
    [[ -f "$f" ]] || { echo -1; return; }
    echo $(( ( $(date +%s) - $(cat "$f") ) / 86400 ))
}
upd_age_label() {                      # human-readable label
    local d; d="$(upd_age_days "$1")"
    if   [[ "$d" -lt 0 ]]; then echo "never"
    elif [[ "$d" -eq 0 ]]; then echo "today"
    else echo "${d}d ago"; fi
}

# ── Flatpak ───────────────────────────────────────────────────────────────
# flatpak_count            → integer number of user apps with updates
# flatpak_update_rows      → lines "appid<TAB>current<TAB>available"
# flatpak_last_label       → when flatpak was last updated by us
flatpak_count() {
    command -v flatpak >/dev/null 2>&1 || { echo 0; return; }
    # grep -c prints 0 and exits 1 when there are no matches; swallow the exit.
    flatpak remote-ls --user --updates 2>/dev/null | grep -c . || true
}
flatpak_update_rows() {
    command -v flatpak >/dev/null 2>&1 || return 0
    local updates cur
    updates="$(flatpak remote-ls --user --updates --columns=application,version 2>/dev/null)" || return 0
    [[ -z "$updates" ]] && return 0
    while IFS=$'\t' read -r appid avail; do
        [[ -z "$appid" ]] && continue
        cur="$(flatpak info --user "$appid" 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}')"
        [[ -z "$cur" ]] && cur="—"
        printf '%s\t%s\t%s\n' "$appid" "$cur" "$avail"
    done <<< "$updates"
}
flatpak_last_label() { upd_age_label "flatpak"; }

# ── rpm-ostree (Fedora OS) ────────────────────────────────────────────────
# The check is slow and network-flaky, so callers run os_check_raw ONCE and
# pass the captured text to the os_parse_* helpers (no repeated subshell calls).
os_check_raw()  { rpm-ostree upgrade --check 2>&1 || true; }   # call once, capture
os_staged()     { rpm-ostree status 2>/dev/null | grep -q "(staged)" && echo 1 || echo 0; }

os_parse_pending() {                   # $1 = raw check text
    printf '%s' "$1" | grep -q "AvailableUpdate:" && echo 1 || echo 0
}
os_parse_version() {                   # $1 = raw check text
    printf '%s\n' "$1" | awk -F": " '/^[[:space:]]*Version:/ {print $2; exit}'
}
os_parse_pkgcount() {                  # $1 = raw check text
    printf '%s\n' "$1" | grep -oP '^\s*Diff:\s*\K[0-9]+' | head -1 || true
}
os_parse_sec() {                       # $1 = severity, $2 = raw check text
    local line
    line="$(printf '%s\n' "$2" | awk -F": " '/SecAdvisories:/ {print $2}' | head -1)"
    local n; n="$(printf '%s' "$line" | grep -oiP "[0-9]+(?=[[:space:]]+$1)" | head -1)"
    echo "${n:-0}"
}
os_current_version() {
    rpm-ostree status --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['deployments'][0].get('version',''))" 2>/dev/null
}
os_last_label() {
    local ts
    ts="$(rpm-ostree status --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['deployments'][0].get('timestamp',0))" 2>/dev/null)"
    [[ -z "$ts" || "$ts" == "0" ]] && { echo "unknown"; return; }
    date -d "@$ts" +%Y-%m-%d 2>/dev/null || echo "unknown"
}

# ── Containers (distrobox + toolbox, discovered dynamically) ──────────────
# discover_distrobox    → container names, one per line
# discover_toolbox      → container names, one per line
# container_is_stale <name> → 0 (stale/never) or 1 (fresh) as exit code
discover_distrobox() {
    command -v distrobox >/dev/null 2>&1 || return 0
    distrobox list --no-color 2>/dev/null \
        | awk -F'|' '/^[0-9a-f]{12}/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}'
}
discover_toolbox() {
    command -v toolbox >/dev/null 2>&1 || return 0
    toolbox list --containers 2>/dev/null | awk 'NR>1 && NF>=2 {print $2}'
}
container_is_stale() {                 # exit 0 = stale (needs attention)
    local d; d="$(upd_age_days "container-$1")"
    [[ "$d" -lt 0 || "$d" -ge "$CONTAINER_STALE_DAYS" ]]
}

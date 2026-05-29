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
# Flatpak apps live across one or more installations (user, system, or custom
# ones in /etc/flatpak/installations.d/). Discover them dynamically rather than
# assuming scopes, then query each — flatpak reports all apps in an
# installation in a single call, so we don't loop over individual apps.
flatpak_installations() {              # installation names that actually hold apps
    command -v flatpak >/dev/null 2>&1 || return 0
    flatpak list --columns=installation 2>/dev/null | sort -u
}
_flatpak_scope_arg() {                 # map installation name → flatpak scope flag
    case "$1" in
        user)   echo "--user" ;;
        system) echo "--system" ;;
        *)      echo "--installation=$1" ;;
    esac
}
flatpak_count() {
    command -v flatpak >/dev/null 2>&1 || { echo 0; return; }
    local total=0 inst scope n
    while IFS= read -r inst; do
        [[ -z "$inst" ]] && continue
        scope="$(_flatpak_scope_arg "$inst")"
        n="$(flatpak remote-ls $scope --updates 2>/dev/null | grep -c . || true)"
        total=$(( total + n ))
    done < <(flatpak_installations)
    echo "$total"
}
flatpak_update_rows() {                # echoes "appid<TAB>current<TAB>available"
    command -v flatpak >/dev/null 2>&1 || return 0
    local inst scope updates cur appid avail
    while IFS= read -r inst; do
        [[ -z "$inst" ]] && continue
        scope="$(_flatpak_scope_arg "$inst")"
        updates="$(flatpak remote-ls $scope --updates --columns=application,version 2>/dev/null)" || continue
        [[ -z "$updates" ]] && continue
        while IFS=$'\t' read -r appid avail; do
            [[ -z "$appid" ]] && continue
            cur="$(flatpak info $scope "$appid" 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}')"
            [[ -z "$cur" ]] && cur="—"
            printf '%s\t%s\t%s\n' "$appid" "$cur" "$avail"
        done <<< "$updates"
    done < <(flatpak_installations)
}
# Real last-updated date from flatpak's own history (native source).
flatpak_last_label() {
    command -v flatpak >/dev/null 2>&1 || { echo "unknown"; return; }
    local t
    t="$(flatpak history --columns=time,change 2>/dev/null \
         | awk -F'\t' '/update|deploy/ {last=$1} END{print last}')"
    [[ -z "$t" ]] && { echo "unknown"; return; }
    date -d "$t" +%Y-%m-%d 2>/dev/null || printf '%s' "$t"
}

# ── rpm-ostree (Fedora OS) ────────────────────────────────────────────────
# The check is slow and network-flaky, so callers run os_check_raw ONCE and
# pass the captured text to the os_parse_* helpers (no repeated subshell calls).
os_check_raw()  { rpm-ostree upgrade --check 2>&1 || true; }   # call once, capture
os_staged()     { rpm-ostree status 2>/dev/null | grep -q "(staged)" && echo 1 || echo 0; }

# ── "Last known good" cache (professional stale-fallback pattern) ──────────
# When a repo is unreachable the live check fails; rather than lie "up to
# date", we keep the last SUCCESSFUL check and show its date. Like apt/dnf
# serving cached metadata when offline.
OS_CACHE_FILE="$CACHE_DIR/os-check.cache"
OS_CACHE_TS_FILE="$CACHE_DIR/os-check.ts"

# Refresh the cache from a live check (3 retries for transient repo hiccups).
# Echoes freshness: "fresh" (just checked OK) | "stale" (using old cache) | "none".
os_refresh_cache() {
    local out try
    for try in 1 2 3; do
        out="$(os_check_raw)"
        if [[ "$(os_parse_state "$out")" != "unknown" ]]; then
            mkdir -p "$CACHE_DIR"
            printf '%s' "$out" > "$OS_CACHE_FILE"
            date +%s > "$OS_CACHE_TS_FILE"
            echo "fresh"; return
        fi
        sleep 1
    done
    [[ -f "$OS_CACHE_FILE" ]] && echo "stale" || echo "none"
}
os_cached_raw() { cat "$OS_CACHE_FILE" 2>/dev/null; }
os_cache_date() {                      # date label of the last successful check
    [[ -f "$OS_CACHE_TS_FILE" ]] || { echo "never"; return; }
    date -d "@$(cat "$OS_CACHE_TS_FILE")" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown"
}

os_parse_pending() {                   # $1 = raw check text
    printf '%s' "$1" | grep -q "AvailableUpdate:" && echo 1 || echo 0
}
# os_parse_state: "pending" | "current" | "unknown"
# "unknown" means the check could not complete (e.g. a repo was unreachable),
# so we must NOT claim the system is up to date.
os_parse_state() {                     # $1 = raw check text
    if   printf '%s' "$1" | grep -q "AvailableUpdate:";                    then echo "pending"
    elif printf '%s' "$1" | grep -qiE "no upgrade available|no updates available"; then echo "current"
    elif printf '%s' "$1" | grep -qiE "error:|could not connect|cannot update repo"; then echo "unknown"
    else echo "current"; fi
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
# Total security advisories (all severities summed) = the "Important" bucket.
os_parse_sec_total() {                 # $1 = raw check text
    local i m l u
    i="$(os_parse_sec important "$1")"; m="$(os_parse_sec moderate "$1")"
    l="$(os_parse_sec low "$1")";       u="$(os_parse_sec unknown "$1")"
    echo $(( i + m + l + u ))
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
# Effective "last touched" epoch: our update timestamp if present, else the
# podman container creation time (a freshly created container is not stale).
container_epoch() {                    # echoes epoch seconds, 0 if unknown
    local name="$1" f ts
    f="$(upd_ts_file "container-$name")"
    [[ -f "$f" ]] && { cat "$f"; return; }
    # Go template .Unix avoids the unparseable "+0100 BST" string from date -d
    ts="$(podman inspect "$name" --format '{{.Created.Unix}}' 2>/dev/null)"
    [[ "$ts" =~ ^[0-9]+$ ]] && { echo "$ts"; return; }
    echo 0
}
container_age_label() {                # human label from effective epoch
    local e; e="$(container_epoch "$1")"
    [[ "$e" -eq 0 ]] && { echo "unknown"; return; }
    local d=$(( ( $(date +%s) - e ) / 86400 ))
    if   [[ "$d" -le 0 ]]; then echo "today"
    else echo "${d}d ago"; fi
}
container_is_stale() {                 # exit 0 = stale (needs attention)
    local e; e="$(container_epoch "$1")"
    [[ "$e" -eq 0 ]] && return 0
    local d=$(( ( $(date +%s) - e ) / 86400 ))
    [[ "$d" -ge "$CONTAINER_STALE_DAYS" ]]
}

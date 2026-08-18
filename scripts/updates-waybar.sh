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
CACHE_MAX_AGE=10800    # background-refresh the cache when older than 3 hours

json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'; }
emit() {
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' \
        "$(printf '%s' "$1" | json_escape)" \
        "$(printf '%s' "$2" | json_escape)" \
        "$(printf '%s' "$3" | json_escape)"
}

# ── Heavy worker: compute everything and write the cache atomically ────────
compute_and_cache() {
    local total=0 os_is_staged=0 sec_high=0 unknown=0
    local lines=()

    # Flatpak (first — most frequently updated).
    # `flatpak_count` returns non-zero when a remote could not be reached. Silence
    # from a check that never ran is not the same as "nothing to update", and
    # saying "up to date" for it is the failure this whole module exists to avoid.
    local fp fp_rc
    fp=$(flatpak_count) && fp_rc=0 || fp_rc=$?
    if [[ "$fp_rc" -ne 0 ]]; then
        lines+=("Flatpak: could not check (remote unreachable) — last updated $(flatpak_last_label)")
        unknown=$(( unknown + 1 ))
    elif [[ "$fp" -gt 0 ]]; then
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

    # User-local apps (GitHub-release tools without a package/self updater, e.g. yazi)
    local ul_rows ul; ul_rows="$(userlocal_update_rows)"
    ul="$(printf '%s' "$ul_rows" | grep -c . || true)"
    if [[ "$ul" -gt 0 ]]; then
        lines+=("User-local apps: $ul update(s)")
        while IFS=$'\t' read -r uname ucur unew; do
            [[ -z "$uname" ]] && continue
            lines+=("  $uname: $ucur → $unew")
        done <<< "$ul_rows"
        total=$(( total + ul ))
    fi

    # Fedora OS (last-known-good cache; stale fallback when repo offline)
    local os_fresh os_raw os_state stale_note=""
    os_fresh="$(os_refresh_cache)"
    os_raw="$(os_cached_raw)"
    os_state="$(os_parse_state "$os_raw")"
    [[ "$os_fresh" == "stale" ]] && stale_note=" (as of $(os_cache_date), repo offline)"

    if [[ "$(os_staged)" -eq 1 ]]; then
        os_is_staged=1; lines+=("OS: staged update — reboot to apply"); total=$(( total + 1 ))
    elif [[ "$os_fresh" == "none" ]]; then
        # Never checked and no last-known-good to fall back on. This used to add
        # nothing to the badge, so "I have no idea" rendered identically to
        # "all clear".
        lines+=("OS: could not check (repo unreachable, no cached result)")
        unknown=$(( unknown + 1 ))
    elif [[ "$os_state" == "pending" ]]; then
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

    # Severity class — the colour encodes the action required of the user:
    #   uptodate (grey)    nothing to do
    #   warning  (amber)   updates available (apps / containers / OS) — run the updater
    #   critical (red)     a deployment is staged — reboot required / pending
    # OS pending packages and security count toward the badge (amber) but never
    # turn it red; only an actually staged update (awaiting reboot) is red.
    # A source that could not be checked counts as "needs your attention" (amber),
    # never as "nothing to do" (grey). Grey must mean "I checked, and it is clean".
    local klass
    if   [[ "$total" -eq 0 && "$unknown" -eq 0 ]]; then klass="uptodate"
    elif [[ "$os_is_staged" -eq 1 ]];              then klass="critical"
    else                                                klass="warning"; fi

    local tooltip result
    tooltip="$(printf '%s\n' "${lines[@]}")"
    result="$(emit "⬆" "$klass" "$tooltip")"

    # Write atomically so Waybar never reads a half-written file.
    mkdir -p "$CACHE_DIR"
    printf '%s\n' "$result" > "$CACHE_FILE.tmp" && mv -f "$CACHE_FILE.tmp" "$CACHE_FILE"
    printf '%s\n' "$result"

    # Push: the module declares "signal": 8, so SIGRTMIN+8 makes Waybar re-run
    # its exec at once and pick up the cache we just wrote. This is what keeps the
    # icon responsive without a fast poll interval — every recompute (menu action,
    # post-reboot, periodic) announces itself the moment fresh data is ready.
    # -x: exact process-name match. Without it the pattern "waybar" also matches
    # this very script ("updates-waybar.sh"), which would signal/kill ourselves
    # and any concurrent instance. Only the real Waybar binary is named "waybar".
    pkill -RTMIN+8 -x waybar 2>/dev/null || true
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

# Default (Waybar) mode — always instant: print the cached JSON, then decide
# whether to kick off a background recompute. The recompute (not the poll) is what
# keeps the icon correct: it signals Waybar when done. Waybar's poll interval is
# therefore just a slow heartbeat, so it can be long — no fast 5s polling needed.
SESSION_MARKER="${XDG_RUNTIME_DIR:-/tmp}/waybar-updates.session"
need_refresh=0

if [[ -f "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    [[ "$age" -ge "$CACHE_MAX_AGE" ]] && need_refresh=1   # periodic discovery of new updates
else
    emit "⬆" "uptodate" "Checking for updates…"           # no cache yet
    need_refresh=1
fi

# First run of this login session (e.g. right after a reboot): force one refresh
# so a staged update applied by the reboot is reflected even when the cache is
# younger than CACHE_MAX_AGE. XDG_RUNTIME_DIR is wiped on logout/reboot, so the
# marker's absence reliably means "first time since boot".
if [[ ! -f "$SESSION_MARKER" ]]; then
    : > "$SESSION_MARKER" 2>/dev/null
    need_refresh=1
fi

[[ "$need_refresh" -eq 1 ]] && spawn_refresh
exit 0

#!/bin/bash
# updates-menu.sh — interactive update menu, runs inside a foot terminal.
# Launched by updates-do.sh. Uses lib-updates.sh for all detection.
# Deliberately NOT 'set -e': updates continue on error and report a summary.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-updates.sh
source "$SCRIPT_DIR/lib-updates.sh"

bar() { printf '%s\n' "────────────────────────────────────────────────────"; }

# ── Summary screen (always shows every section) ──────────────────────────
show_summary() {
    clear
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   System Updates                                 ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "Checking… (querying repositories)"

    # Gather once
    FP_COUNT="$(flatpak_count)"
    OS_RAW="$(os_check_raw)"
    OS_STAGED="$(os_staged)"
    OS_STATE="$(os_parse_state "$OS_RAW")"
    OS_PENDING="$(os_parse_pending "$OS_RAW")"

    clear
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   System Updates                                 ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    # ── Flatpak ──
    echo "  Flatpak apps          last updated: $(flatpak_last_label)"
    echo "    Updates:    $FP_COUNT"
    echo ""

    # ── Containers (dynamic) ──
    echo "  Containers"
    local found=0
    while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        found=1
        local mark=""; container_is_stale "$c" && mark=" ⚠"
        printf '    %-22s last updated: %s%s\n' "$c" "$(container_age_label "$c")" "$mark"
    done < <(discover_distrobox; discover_toolbox)
    [[ "$found" -eq 0 ]] && echo "    (none found)"
    echo ""

    # ── Fedora OS ──
    echo "  Fedora OS             last updated: $(os_last_label)"
    echo "    Current:    $(os_current_version)"
    if [[ "$OS_STAGED" -eq 1 ]]; then
        echo "    Available:  staged — reboot to apply"
        echo "    Packages:   (staged)"
    elif [[ "$OS_PENDING" -eq 1 ]]; then
        echo "    Available:  $(os_parse_version "$OS_RAW")"
        echo "    Packages:   $(os_parse_pkgcount "$OS_RAW")  (total to upgrade)"
    elif [[ "$OS_STATE" == "unknown" ]]; then
        echo "    Available:  check unavailable (a repo is unreachable)"
        echo "    Packages:   ?"
    else
        echo "    Available:  up to date"
        echo "    Packages:   0"
    fi
    if [[ "$OS_PENDING" -eq 1 ]]; then
        local sec reg pc
        sec="$(os_parse_sec_total "$OS_RAW")"
        pc="$(os_parse_pkgcount "$OS_RAW")"
        reg=$(( ${pc:-0} - sec )); [[ "$reg" -lt 0 ]] && reg=0
        echo "    Security:   $sec  (packages with a security advisory)"
        echo "    Regular:    $reg  (all other updates)"
    fi
    echo ""
    bar
}

# ── Update actions (each returns 0 on success, 1 on failure) ──────────────
do_flatpak() {
    echo ""; echo "── Updating Flatpak apps ────────────────────────────"
    if flatpak update --user -y --noninteractive; then upd_record flatpak; return 0; fi
    echo "  Retry after flatpak repair…"
    flatpak repair --user 2>/dev/null || true
    if flatpak update --user -y --noninteractive; then upd_record flatpak; return 0; fi
    return 1
}

do_containers() {
    local rc=0 name
    # distrobox containers — distrobox upgrade picks the right package manager
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        echo ""; echo "── Updating distrobox: $name ────────────────────────"
        if distrobox upgrade "$name"; then upd_record "container-$name"
        else echo "  ✗ $name failed (continuing)"; rc=1; fi
    done < <(discover_distrobox)
    # toolbox containers — dnf inside
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        echo ""; echo "── Updating toolbox: $name ──────────────────────────"
        if toolbox run --container "$name" sudo dnf upgrade -y --skip-unavailable; then upd_record "container-$name"
        else echo "  ✗ $name failed (continuing)"; rc=1; fi
    done < <(discover_toolbox)
    return "$rc"
}

do_os() {
    echo ""; echo "── Updating Fedora OS ───────────────────────────────"
    # rpm-ostree is atomic: a failed upgrade leaves the current deployment intact,
    # so there is nothing to "repair" — just report success or failure.
    if rpm-ostree upgrade; then
        echo "  ✔ OS update staged. Reboot required to apply."
        return 0
    fi
    return 1
}

ask_reboot() {
    echo ""; read -rp "  Reboot now to apply the OS update? [y/N] " rb
    [[ "$rb" =~ ^[Yy]$ ]] && systemctl reboot
}

# ── Show update list (scrollable, returns to menu) ────────────────────────
show_list() {
    {
        echo "╔══════════════════════════════════════════════════╗"
        echo "║   Update List                                    ║"
        echo "╚══════════════════════════════════════════════════╝"
        echo ""
        local NAME_W=44 VER_W=22

        # Flatpak — count here equals the menu count (same source)
        local fp; fp="$(flatpak_count)"
        echo "FLATPAK APPS ($fp)"
        if [[ "$fp" -gt 0 ]]; then
            printf '  %-*s  %-*s    %s\n' "$NAME_W" "Package" "$VER_W" "Current" "New"
            printf '  %s\n' "$(printf '─%.0s' $(seq 1 $((NAME_W + VER_W + 18))))"
            while IFS=$'\t' read -r appid cur avail; do
                [[ -z "$appid" ]] && continue
                printf '  %-*s  %-*s →  %s\n' "$NAME_W" "$appid" "$VER_W" "$cur" "$avail"
            done < <(flatpak_update_rows)
        else
            echo "  (up to date)"
        fi
        echo ""

        # OS — table of package name | current → new
        echo "FEDORA OS"
        local os_raw; os_raw="$(os_check_raw)"
        if [[ "$(os_parse_pending "$os_raw")" -eq 1 ]]; then
            local sec pc reg
            sec="$(os_parse_sec_total "$os_raw")"; pc="$(os_parse_pkgcount "$os_raw")"
            reg=$(( ${pc:-0} - sec )); [[ "$reg" -lt 0 ]] && reg=0
            printf '  %s → %s   (Security: %s, Regular: %s)\n\n' \
                "$(os_current_version)" "$(os_parse_version "$os_raw")" "$sec" "$reg"
            printf '  %-*s  %-*s    %s\n' "$NAME_W" "Package" "$VER_W" "Current" "New"
            printf '  %s\n' "$(printf '─%.0s' $(seq 1 $((NAME_W + VER_W + 18))))"
            # Parse "name oldver -> newver" from the Upgraded: section
            rpm-ostree upgrade --preview 2>/dev/null \
                | awk '/Upgraded:/{p=1;next} /Removed:|Added:|Downgraded:/{p=0} p && NF>=3 {print}' \
                | awk -v nw="$NAME_W" -v vw="$VER_W" \
                    '{ name=$1; old=$2; new=$4; printf "  %-*s  %-*s →  %s\n", nw, name, vw, old, new }'
        else
            echo "  (up to date)"
        fi
        echo ""

        # Containers
        echo "CONTAINERS"
        local found=0 name
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            found=1
            printf '  %-*s  last updated: %s\n' "$NAME_W" "$name" "$(container_age_label "$name")"
        done < <(discover_distrobox; discover_toolbox)
        [[ "$found" -eq 0 ]] && echo "  (none found)"
        echo ""
        echo "(Container package details require entering the container.)"
    } | less -R
}

# ── Refresh Waybar after any change ──────────────────────────────────────
refresh_waybar() {
    rm -f "$CACHE_DIR/waybar-updates.json"
    pkill -SIGRTMIN+8 waybar 2>/dev/null || true
}

# ── Run "everything" with continue-on-error + summary ─────────────────────
do_everything() {
    local r_fp r_ct r_os
    do_flatpak;    r_fp=$?
    do_containers; r_ct=$?
    do_os;         r_os=$?
    echo ""; bar
    echo "  Results:"
    [[ "$r_fp" -eq 0 ]] && echo "    ✔ Flatpak apps updated"      || echo "    ✗ Flatpak apps failed"
    [[ "$r_ct" -eq 0 ]] && echo "    ✔ Containers updated"        || echo "    ✗ Some containers failed"
    [[ "$r_os" -eq 0 ]] && echo "    ✔ Fedora OS staged"          || echo "    ✗ Fedora OS failed"
    [[ "$r_os" -eq 0 ]] && ask_reboot
}

# ── Main loop ─────────────────────────────────────────────────────────────
while true; do
    show_summary
    echo ""
    echo "  What would you like to do?"
    echo ""
    echo "    1) Update Flatpak apps      (fastest, no reboot)"
    echo "    2) Update containers        (no reboot)"
    echo "    3) Update Fedora OS         (reboot required)"
    echo "    4) Update everything        (apps → containers → OS)"
    echo "    5) Show update list"
    echo "    q) Cancel"
    echo ""
    read -rp "  Choice: " choice

    case "$choice" in
        1) do_flatpak    && echo "  ✔ Done." || echo "  ✗ Failed."; refresh_waybar
           echo ""; read -rp "  Press Enter to return to menu…" _ ;;
        2) do_containers && echo "  ✔ Done." || echo "  ✗ Some failed."; refresh_waybar
           echo ""; read -rp "  Press Enter to return to menu…" _ ;;
        3) if do_os; then ask_reboot; fi; refresh_waybar
           echo ""; read -rp "  Press Enter to return to menu…" _ ;;
        4) do_everything; refresh_waybar
           echo ""; read -rp "  Press Enter to return to menu…" _ ;;
        5) show_list ;;                       # less → returns straight to menu
        q|Q|"") break ;;
        *) echo "  Unknown option."; sleep 1 ;;
    esac
done

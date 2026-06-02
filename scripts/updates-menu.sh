#!/bin/bash
# updates-menu.sh — interactive update menu, runs inside a foot terminal.
# Launched by updates-do.sh. Uses lib-updates.sh for all detection.
# Deliberately NOT 'set -e': updates continue on error and report a summary.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-updates.sh
source "$SCRIPT_DIR/lib-updates.sh"

bar() { printf '%s\n' "────────────────────────────────────────────────────"; }

# ── Logging ───────────────────────────────────────────────────────────────
# Every update action is timestamped and tee'd to a persistent log, so if an
# update fails the output survives after the terminal closes.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG="$LOG_DIR/dotfiles-updates.log"
mkdir -p "$LOG_DIR"
log_line()   { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
# Run a command showing output on screen AND appending it to the log.
# pipefail (set at top) makes the pipeline keep the command's exit code.
run_logged() { "$@" 2>&1 | tee -a "$LOG"; }

# OS check uses the shared "last known good" cache from lib-updates.sh:
# os_refresh_cache() does a live check (with retries) and falls back to the
# last successful result when a repo is unreachable. OS_FRESHNESS records
# whether the data is fresh / stale / never-checked for this session.
OS_FRESHNESS="fresh"
refresh_os_cache() { OS_FRESHNESS="$(os_refresh_cache)"; }
os_raw_cached()    { os_cached_raw; }

# ── Summary screen (always shows every section) ──────────────────────────
show_summary() {
    # Gather (OS comes from the per-session cache, not a fresh slow check)
    FP_COUNT="$(flatpak_count)"
    OS_RAW="$(os_raw_cached)"
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
    elif [[ "$OS_FRESHNESS" == "none" ]]; then
        echo "    Available:  not yet checked (repo unreachable)"
        echo "    Packages:   ?"
    elif [[ "$OS_PENDING" -eq 1 ]]; then
        echo "    Available:  $(os_parse_version "$OS_RAW")"
        echo "    Packages:   $(os_parse_pkgcount "$OS_RAW")  (total to upgrade)"
        [[ "$OS_FRESHNESS" == "stale" ]] && echo "    Checked:    $(os_cache_date)  (cached — repo offline now)"
    else
        echo "    Available:  up to date"
        echo "    Packages:   0"
        [[ "$OS_FRESHNESS" == "stale" ]] && echo "    Checked:    $(os_cache_date)  (cached — repo offline now)"
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
    local rc=0 inst scope ans app
    # A running app keeps the OLD version until its background process is fully
    # killed — closing the window (e.g. Alt+Shift+Q in Sway) only hides it;
    # Chromium/Electron apps keep a master process alive. So before updating we
    # find apps that (a) have a pending update and (b) are running, and offer
    # to close them so the new version actually takes effect.
    local running_updated
    running_updated="$(comm -12 \
        <(flatpak_update_rows | cut -f1 | sort -u) \
        <(flatpak ps --columns=application 2>/dev/null | sort -u) 2>/dev/null)"

    if [[ -n "$running_updated" ]]; then
        echo ""
        echo "  ⚠ These apps have an update AND are running right now:"
        printf '%s\n' "$running_updated" | sed 's/^/      • /'
        echo ""
        echo "    A running app keeps the OLD version until its background"
        echo "    process is closed. Closing just the window does NOT stop"
        echo "    browsers / Electron apps — they keep a master process alive."
        echo "    Save any unsaved work first; apps are asked to close (SIGTERM)."
        echo ""
        read -rp "  Close these apps now and continue with the update? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            # 1) graceful SIGTERM via flatpak kill
            while IFS= read -r app; do
                [[ -z "$app" ]] && continue
                echo "    Closing $app…"; log_line "flatpak kill (SIGTERM) $app"
                flatpak kill "$app" 2>/dev/null || true
            done <<< "$running_updated"
            sleep 2
            # 2) escalate to SIGKILL for any that ignored SIGTERM (Electron masters)
            local survivors
            survivors="$(comm -12 \
                <(printf '%s\n' "$running_updated" | sort -u) \
                <(flatpak ps --columns=application 2>/dev/null | sort -u) 2>/dev/null)"
            if [[ -n "$survivors" ]]; then
                while IFS= read -r app; do
                    [[ -z "$app" ]] && continue
                    echo "    $app ignored close — forcing (SIGKILL)…"; log_line "flatpak kill -s SIGKILL $app"
                    flatpak kill -s SIGKILL "$app" 2>/dev/null || true
                done <<< "$survivors"
                sleep 1
            fi
            # 3) report anything STILL alive (couldn't be killed)
            local still
            still="$(comm -12 \
                <(printf '%s\n' "$running_updated" | sort -u) \
                <(flatpak ps --columns=application 2>/dev/null | sort -u) 2>/dev/null)"
            if [[ -n "$still" ]]; then
                echo "  ⚠ Could not stop these — restart them manually after the update:"
                printf '%s\n' "$still" | sed 's/^/      • /'
                log_line "STILL RUNNING after kill: $(printf '%s ' $still)"
            fi
        else
            echo "  Leaving them open — restart them yourself afterwards to apply."
            log_line "user declined closing running apps"
        fi
    fi

    # Iterate the discovered installations (user needs no auth; system/custom
    # use polkit — an interactive prompt is fine, the user opened this menu).
    # FD 3 so `flatpak update` reading stdin can't swallow the rest of the list.
    while IFS= read -r inst <&3; do
        [[ -z "$inst" ]] && continue
        scope="$(_flatpak_scope_arg "$inst")"
        echo ""; echo "── Updating Flatpak ($inst) ─────────────────────────"
        log_line "BEGIN Flatpak update ($inst)"
        if run_logged flatpak update $scope -y; then
            log_line "OK Flatpak ($inst)"
        else
            log_line "FAIL Flatpak ($inst)"; echo "  ✗ $inst scope failed. Log: $LOG"; rc=1
        fi
    done 3< <(flatpak_installations)
    [[ "$rc" -eq 0 ]] && upd_record flatpak
    return "$rc"
}

# Package-manager-agnostic upgrade command run inside any container.
CONTAINER_UPGRADE_CMD='
    if   command -v dnf     >/dev/null 2>&1; then sudo dnf upgrade -y --skip-unavailable
    elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get upgrade -y
    elif command -v zypper  >/dev/null 2>&1; then sudo zypper -n update
    elif command -v pacman  >/dev/null 2>&1; then sudo pacman -Syu --noconfirm
    elif command -v apk     >/dev/null 2>&1; then sudo apk upgrade
    else echo "no known package manager in this container"; exit 1; fi'

# Ensure passwordless sudo inside a container so updates never hang on a hidden
# password prompt (distrobox sets this up automatically; toolbox may not). If it
# is missing, ask the user once for their password to install a NOPASSWD rule —
# after that every future update is silent, consistent with distrobox.
# $1 = "toolbox"|"distrobox", $2 = container name. Returns 0 if sudo is usable.
ensure_container_nopasswd() {
    local kind="$1" name="$2" runner
    [[ "$kind" == "toolbox" ]] && runner=(toolbox run --container "$name") \
                               || runner=(distrobox enter "$name" --)
    # Already passwordless?
    if "${runner[@]}" sudo -n true >/dev/null 2>&1; then return 0; fi
    echo "  ⚠ '$name' has no passwordless sudo — updates would hang on a prompt."
    echo "    Setting up a one-time NOPASSWD rule (asks your password once)…"
    log_line "configuring NOPASSWD sudo in $name"
    # This single sudo call prompts on the real terminal; afterwards it's silent.
    if "${runner[@]}" bash -c \
        "sudo install -m 0440 /dev/stdin /etc/sudoers.d/00-nopasswd-\$USER <<<\"\$USER ALL=(root) NOPASSWD:ALL\""; then
        echo "    ✓ passwordless sudo configured for '$name'."
        return 0
    fi
    echo "    ✗ could not configure sudo for '$name' — skipping it."
    log_line "FAILED to configure NOPASSWD in $name"
    return 1
}

do_containers() {
    local rc=0 name
    local failed=()        # names of containers that failed, for a clear summary
    # NOTE: read the container list on FD 3, not stdin. Commands inside the loop
    # (distrobox upgrade → apt, toolbox run → sudo) read stdin and would otherwise
    # consume the rest of the list, silently skipping later containers (this is
    # why damianu was skipped after security). Inner commands keep the real TTY
    # on FD 0 so sudo can still prompt when needed.
    # distrobox containers — distrobox upgrade picks the right package manager
    # and distrobox already provides passwordless sudo.
    while IFS= read -r name <&3; do
        [[ -z "$name" ]] && continue
        echo ""; echo "── Updating distrobox: $name ────────────────────────"
        log_line "BEGIN distrobox upgrade $name"
        if run_logged distrobox upgrade "$name"; then
            upd_record "container-$name"; log_line "OK distrobox $name"
        else
            echo "  ✗ $name failed (continuing)."; log_line "FAIL distrobox $name"; failed+=("$name"); rc=1
        fi
    done 3< <(discover_distrobox)
    # toolbox containers — ensure passwordless sudo first, then upgrade with the
    # detected package manager.
    while IFS= read -r name <&3; do
        [[ -z "$name" ]] && continue
        echo ""; echo "── Updating toolbox: $name ──────────────────────────"
        log_line "BEGIN toolbox upgrade $name"
        if ! ensure_container_nopasswd toolbox "$name"; then failed+=("$name (sudo)"); rc=1; continue; fi
        if run_logged toolbox run --container "$name" bash -c "$CONTAINER_UPGRADE_CMD"; then
            upd_record "container-$name"; log_line "OK toolbox $name"
        else
            echo "  ✗ $name failed (continuing)."; log_line "FAIL toolbox $name"; failed+=("$name"); rc=1
        fi
    done 3< <(discover_toolbox)
    # Clear summary so the user always knows exactly what failed and where.
    if [[ "${#failed[@]}" -gt 0 ]]; then
        echo ""
        echo "  ⚠ These containers did NOT update:"
        printf '%s\n' "${failed[@]}" | sed 's/^/      • /'
        echo "    Full output: $LOG"
    fi
    return "$rc"
}

do_os() {
    echo ""; echo "── Updating Fedora OS ───────────────────────────────"
    log_line "BEGIN rpm-ostree upgrade"
    # rpm-ostree is atomic: a failed upgrade leaves the current deployment intact.
    # NOTE: `rpm-ostree upgrade` exits 0 even when there is nothing to upgrade
    # ("No upgrade available"), so command success does NOT imply an update was
    # staged. Ask the deployment state itself (os_staged checks status for
    # "(staged)") to decide whether a reboot is actually warranted.
    if ! run_logged rpm-ostree upgrade; then
        log_line "FAIL rpm-ostree upgrade — see log"
        echo "  ✗ OS update failed (system unchanged — rpm-ostree is atomic). Log: $LOG"
        return 1
    fi
    if [[ "$(os_staged)" -eq 1 ]]; then
        echo "  ✔ OS update staged. Reboot required to apply."
        log_line "OK rpm-ostree upgrade (staged)"
        return 0
    fi
    echo "  ✔ Fedora OS already up to date — nothing staged, no reboot needed."
    log_line "OK rpm-ostree upgrade (no change)"
    return 2
}

ask_reboot() {
    # Recompute the badge before prompting so the icon already shows red
    # ("staged — reboot to apply") while the user decides, instead of only after.
    refresh_waybar
    echo ""; read -rp "  Reboot now to apply the OS update? [y/N] " rb
    [[ "$rb" =~ ^[Yy]$ ]] && systemctl reboot
}

# ── Show update list (scrollable, returns to menu) ────────────────────────
show_list() {
    {
        echo "╔══════════════════════════════════════════════════╗"
        echo "║   Update List   —   scroll: ↑ ↓ / PgUp PgDn      ║"
        echo "║                     press  q  to go back         ║"
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

        # OS — table of package name | current → new (from session cache)
        echo "FEDORA OS"
        local os_raw; os_raw="$(os_raw_cached)"
        if [[ "$(os_parse_pending "$os_raw")" -eq 1 ]]; then
            local sec pc reg
            sec="$(os_parse_sec_total "$os_raw")"; pc="$(os_parse_pkgcount "$os_raw")"
            reg=$(( ${pc:-0} - sec )); [[ "$reg" -lt 0 ]] && reg=0
            printf '  %s → %s   (Security: %s, Regular: %s)\n\n' \
                "$(os_current_version)" "$(os_parse_version "$os_raw")" "$sec" "$reg"
            printf '  %-*s  %-*s    %s\n' "$NAME_W" "Package" "$VER_W" "Current" "New"
            printf '  %s\n' "$(printf '─%.0s' $(seq 1 $((NAME_W + VER_W + 18))))"
            # Parse "name oldver -> newver" from the Upgraded: section.
            # --preview is a separate (flaky) call; if it returns no rows,
            # show a clear fallback instead of a misleading empty table.
            local table
            table="$(rpm-ostree upgrade --preview 2>/dev/null \
                | awk '/Upgraded:/{p=1;next} /Removed:|Added:|Downgraded:/{p=0} p && NF>=3 {print}' \
                | awk -v nw="$NAME_W" -v vw="$VER_W" \
                    '{ name=$1; old=$2; new=$4; printf "  %-*s  %-*s →  %s\n", nw, name, vw, old, new }')"
            if [[ -n "$table" ]]; then
                printf '%s\n' "$table"
            else
                echo "  (package list temporarily unavailable — a repo is busy;"
                echo "   $pc packages are pending, shown above)"
            fi
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
    } | less -R --prompt=' ↑/↓ scroll   ·   press q to return to the menu '
}

# ── Refresh Waybar after any change ──────────────────────────────────────
# Recompute the cache via the heavy worker (--compute) in the background; when it
# finishes it writes the cache and signals Waybar (SIGRTMIN+8) to redraw at once.
# setsid -f fully detaches it so the recompute still completes (and the icon still
# updates) even when this menu's terminal closes right after — e.g. on Cancel.
refresh_waybar() {
    setsid -f "$SCRIPT_DIR/updates-waybar.sh" --compute >/dev/null 2>&1 || \
        ( "$SCRIPT_DIR/updates-waybar.sh" --compute >/dev/null 2>&1 & )
}

# Every exit path (Cancel, Ctrl-C, end of an action) ends with one recompute, so
# the icon always reflects the real post-session state — including an update that
# silently failed (its count stays > 0, so the badge stays lit).
trap refresh_waybar EXIT

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
    case "$r_os" in
        0) echo "    ✔ Fedora OS staged (reboot to apply)" ;;
        2) echo "    ✔ Fedora OS up to date" ;;
        *) echo "    ✗ Fedora OS failed" ;;
    esac
    if [[ "$r_fp" -ne 0 || "$r_ct" -ne 0 || "$r_os" -eq 1 ]]; then
        echo ""; echo "    Some steps failed — full output logged to:"; echo "      $LOG"
    fi
    [[ "$r_os" -eq 0 ]] && ask_reboot
}

# ── Main loop ─────────────────────────────────────────────────────────────
# One OS check at startup (with retries), reused for the whole session so the
# summary and the list always agree. Refreshed only after an OS update.
clear
echo "Checking for updates… (querying repositories, please wait)"
log_line "=== update menu session started ==="
refresh_os_cache

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
        3) if do_os; then ask_reboot; fi; refresh_os_cache; refresh_waybar
           echo ""; read -rp "  Press Enter to return to menu…" _ ;;
        4) do_everything; refresh_os_cache; refresh_waybar
           echo ""; read -rp "  Press Enter to return to menu…" _ ;;
        5) show_list; refresh_waybar ;;       # less → returns straight to menu
        q|Q|"") break ;;
        *) echo "  Unknown option."; sleep 1 ;;
    esac
done

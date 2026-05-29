#!/bin/bash
# Update handler — fully dynamic, no hardcoded container names (UK English)
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"

foot --title "system-updates" bash -c '
set -euo pipefail
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
THRESHOLD_DAYS=7

# ── Helper: human-readable age ───────────────────────────
age_label() {
    local f="$CACHE_DIR/container-last-update-$1"
    [[ ! -f "$f" ]] && echo "never updated" && return
    local d=$(( ( $(date +%s) - $(cat "$f") ) / 86400 ))
    [[ "$d" -eq 0 ]] && echo "today" || echo "${d}d ago"
}

# ── Discover containers dynamically ──────────────────────
mapfile -t distrobox_list < <(
    distrobox list --no-color 2>/dev/null \
    | awk -F"|" "/^[0-9a-f]{12}/ {gsub(/^[[:space:]]+|[[:space:]]+\$/, \"\", \$2); if (\$2 != \"\") print \$2}"
)
mapfile -t toolbox_list < <(
    toolbox list --containers 2>/dev/null \
    | awk "NR>1 && NF>=2 {print \$2}"
)
all_containers=( "${distrobox_list[@]+"${distrobox_list[@]}"}" "${toolbox_list[@]+"${toolbox_list[@]}"}" )

# ── Gather OS info ────────────────────────────────────────
current_ver=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d "\"")
echo "Checking for updates..."
ostree_check=$(rpm-ostree upgrade --check 2>&1 || true)
new_ver=$(printf "%s\n" "$ostree_check" | awk -F": " "/^[[:space:]]*Version:/ {print \$2; exit}")
sec_adv=$(printf "%s\n" "$ostree_check" | awk -F": " "/SecAdvisories:/ {print \$2}")
diff_line=$(printf "%s\n" "$ostree_check" | awk -F": " "/^[[:space:]]*Diff:/ {print \$2}")
os_has_update=0; [[ -n "$new_ver" ]] && os_has_update=1

# ── Gather Flatpak info ───────────────────────────────────
fp_list=$(flatpak remote-ls --user --updates --columns=application,version 2>/dev/null || true)
fp_count=$(printf "%s\n" "$fp_list" | grep -c "." 2>/dev/null || echo 0)
[[ -z "$fp_list" ]] && fp_count=0

clear
echo "╔══════════════════════════════════════════════════╗"
echo "║   System Updates                                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── OS section ───────────────────────────────────────────
echo "  Fedora OS"
echo "    Current:    $current_ver"
if [[ "$os_has_update" -eq 1 ]]; then
    echo "    Available:  $new_ver"
    echo "    Packages:   $diff_line"
    [[ -n "$sec_adv" ]] && echo "    Security:   $sec_adv"
else
    echo "    Status:     Up to date"
fi

# ── Flatpak section ───────────────────────────────────────
echo ""
echo "  Flatpak apps:  $fp_count update(s)"
if [[ "$fp_count" -gt 0 ]]; then
    printf "%s\n" "$fp_list" | awk "{printf \"    %-40s %s\n\", \$1, \$2}" | head -10
    [[ "$fp_count" -gt 10 ]] && echo "    ... and $((fp_count - 10)) more"
fi

# ── Containers section ────────────────────────────────────
echo ""
echo "  Containers (last updated)"
if [[ "${#all_containers[@]}" -eq 0 ]]; then
    echo "    No containers found"
else
    for name in "${all_containers[@]}"; do
        label=$(age_label "$name")
        # Mark stale containers
        f="$CACHE_DIR/container-last-update-$name"
        stale=""
        if [[ ! -f "$f" ]]; then
            stale=" ⚠"
        else
            age=$(( ( $(date +%s) - $(cat "$f") ) / 86400 ))
            [[ "$age" -ge "$THRESHOLD_DAYS" ]] && stale=" ⚠"
        fi
        printf "    %-20s %s%s\n" "$name" "$label" "$stale"
    done
fi

echo ""
echo "────────────────────────────────────────────────────"
echo ""
echo "  What would you like to do?"
echo ""
echo "    1) Update Flatpak apps only     (no reboot needed)"
echo "    2) Update Fedora OS only        (reboot required)"
if [[ "${#all_containers[@]}" -gt 0 ]]; then
    echo "    3) Update containers only"
    echo "    4) Update everything            (Flatpak + OS + containers)"
    [[ "$os_has_update" -eq 1 ]] && echo "    5) Show full OS package list"
else
    echo "    3) Update everything            (Flatpak + OS)"
    [[ "$os_has_update" -eq 1 ]] && echo "    4) Show full OS package list"
fi
echo "    q) Cancel"
echo ""
read -rp "  Choice: " choice

run_flatpak() {
    echo ""; echo "── Updating Flatpak apps ──────────────────────────────"
    flatpak update --user -y
}

run_os() {
    echo ""; echo "── Updating Fedora OS ─────────────────────────────────"
    rpm-ostree upgrade
    echo ""; echo "✔ OS update staged. Reboot required."
}

run_containers() {
    echo ""
    # Distrobox containers
    if [[ "${#distrobox_list[@]}" -gt 0 ]]; then
        echo "── Updating distrobox containers ──────────────────────"
        distrobox upgrade --all
        for name in "${distrobox_list[@]}"; do
            date +%s > "$CACHE_DIR/container-last-update-$name"
        done
    fi
    # Toolbox containers
    for name in "${toolbox_list[@]+"${toolbox_list[@]}"}"; do
        echo "── Updating toolbox: $name ─────────────────────────────"
        toolbox run --container "$name" sudo dnf update -y
        date +%s > "$CACHE_DIR/container-last-update-$name"
    done
    echo ""; echo "✔ Containers updated."
}

ask_reboot() {
    echo ""; read -rp "  Reboot now to apply OS update? [y/N] " rb
    [[ "$rb" =~ ^[Yy]$ ]] && systemctl reboot
}

has_containers=$(( ${#all_containers[@]} > 0 ? 1 : 0 ))

case "$choice" in
    1) run_flatpak; echo ""; echo "✔ Done." ;;
    2) run_os; ask_reboot ;;
    3)
        if [[ "$has_containers" -eq 1 ]]; then run_containers
        else run_flatpak; run_os; ask_reboot; fi ;;
    4)
        if [[ "$has_containers" -eq 1 ]]; then run_flatpak; run_os; run_containers; ask_reboot
        else
            echo ""; echo "── Full OS package list ───────────────────────────────"
            printf "%s\n" "$ostree_check"; echo ""
            read -rp "  Press Enter..." _
        fi ;;
    5)  echo ""; echo "── Full OS package list ───────────────────────────────"
        printf "%s\n" "$ostree_check"; echo ""
        read -rp "  Press Enter..." _ ;;
    q|Q|"") echo "  Cancelled." ;;
    *) echo "  Unknown option." ;;
esac

rm -f "$CACHE_DIR/waybar-updates.json"
pkill -SIGRTMIN+8 waybar 2>/dev/null || true

echo ""; read -rp "  Press Enter to close..." _
'

#!/bin/bash
# Update handler — opens foot terminal with interactive menu (UK English)
set -euo pipefail

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"

foot --title "system-updates" bash -c '
set -euo pipefail

echo "╔══════════════════════════════════════════════════╗"
echo "║   System Updates                                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Gather OS info ────────────────────────────────────────
current_ver=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d "\"")
ostree_check=$(rpm-ostree upgrade --check 2>/dev/null || true)

new_ver=$(printf "%s\n" "$ostree_check" | awk -F": " "/^[[:space:]]*Version:/ {print \$2; exit}")
sec_adv=$(printf "%s\n" "$ostree_check" | awk -F": " "/SecAdvisories:/ {print \$2}")
diff_line=$(printf "%s\n" "$ostree_check" | awk -F": " "/^[[:space:]]*Diff:/ {print \$2}")

os_has_update=0
[[ -n "$new_ver" ]] && os_has_update=1

# ── Gather Flatpak info ───────────────────────────────────
fp_list=$(flatpak remote-ls --user --updates --columns=application,version,origin 2>/dev/null || true)
fp_count=$(printf "%s\n" "$fp_list" | grep -c "." 2>/dev/null || echo 0)
[[ -z "$fp_list" ]] && fp_count=0

# ── Display summary ───────────────────────────────────────
echo "  Fedora OS"
echo "    Current:    $current_ver"
if [[ "$os_has_update" -eq 1 ]]; then
    echo "    Available:  $new_ver"
    echo "    Packages:   $diff_line"
    [[ -n "$sec_adv" ]] && echo "    Security:   $sec_adv"
else
    echo "    Status:     Up to date"
fi
echo ""
echo "  Flatpak apps:  $fp_count update(s) available"
if [[ "$fp_count" -gt 0 ]]; then
    printf "%s\n" "$fp_list" | awk "{printf \"    %-40s %s\n\", \$1, \$2}" | head -10
    [[ "$fp_count" -gt 10 ]] && echo "    ... and $((fp_count - 10)) more"
fi
echo ""
echo "────────────────────────────────────────────────────"
echo ""
echo "  What would you like to do?"
echo ""
echo "    1) Update Flatpak apps only     (no reboot needed)"
echo "    2) Update Fedora OS only        (reboot required)"
echo "    3) Update everything            (Flatpak + OS)"
[[ "$os_has_update" -eq 1 ]] && echo "    4) Show full OS package list"
echo "    q) Cancel"
echo ""
read -rp "  Choice [1/2/3/4/q]: " choice

case "$choice" in
    1)
        echo ""
        echo "── Updating Flatpak apps ────────────────────────────"
        flatpak update --user -y
        echo ""
        echo "✔ Done. No reboot required."
        ;;
    2)
        echo ""
        echo "── Updating Fedora OS ───────────────────────────────"
        rpm-ostree upgrade
        echo ""
        echo "✔ Done. Reboot required to apply OS update."
        echo ""
        read -rp "  Reboot now? [y/N] " rb
        [[ "$rb" =~ ^[Yy]$ ]] && systemctl reboot
        ;;
    3)
        echo ""
        echo "── Updating Flatpak apps ────────────────────────────"
        flatpak update --user -y
        echo ""
        echo "── Updating Fedora OS ───────────────────────────────"
        rpm-ostree upgrade
        echo ""
        echo "✔ Done. Reboot required to apply OS update."
        echo ""
        read -rp "  Reboot now? [y/N] " rb
        [[ "$rb" =~ ^[Yy]$ ]] && systemctl reboot
        ;;
    4)
        echo ""
        echo "── Full OS package list ─────────────────────────────"
        rpm-ostree upgrade --check 2>/dev/null | grep -A9999 "Upgraded:" | head -100 || \
            printf "%s\n" "$ostree_check"
        echo ""
        read -rp "  Press Enter to return to menu..." _
        ;;
    q|Q|"")
        echo "  Cancelled."
        ;;
    *)
        echo "  Unknown option."
        ;;
esac

# Force Waybar to refresh update count
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"
pkill -SIGRTMIN+8 waybar 2>/dev/null || true

echo ""
read -rp "  Press Enter to close..." _
'

#!/bin/bash
# Update handler — opens foot terminal, shows available updates, asks to confirm
set -euo pipefail

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"

foot bash -c '
set -euo pipefail
echo "╔══════════════════════════════════════════╗"
echo "║   System Updates                         ║"
echo "╚══════════════════════════════════════════╝"
echo ""

echo "── rpm-ostree ──────────────────────────────"
rpm-ostree upgrade --check 2>&1 || true
echo ""

echo "── Flatpak (user) ──────────────────────────"
flatpak update --user --no-deploy 2>&1 || true
echo ""
echo "────────────────────────────────────────────"
echo ""
read -rp "Apply all updates now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo ""
    echo "── Updating Flatpak ────────────────────────"
    flatpak update --user -y
    echo ""
    echo "── Updating OS (rpm-ostree) ────────────────"
    echo "Note: reboot required after OS update"
    rpm-ostree upgrade
    echo ""
    echo "DONE."

    # Force Waybar to refresh update count
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"
    pkill -SIGRTMIN+8 waybar 2>/dev/null || true

    echo ""
    read -rp "Reboot now to apply OS update? [y/N] " reboot_ans
    if [[ "$reboot_ans" =~ ^[Yy]$ ]]; then
        systemctl reboot
    fi
else
    echo "No changes made."
fi

echo ""
read -rp "Press Enter to close..." _
'

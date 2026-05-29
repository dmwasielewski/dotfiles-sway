#!/bin/bash
# Update handler — opens foot terminal with interactive menu
set -euo pipefail

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"

foot bash -c '
set -euo pipefail

echo "╔══════════════════════════════════════════╗"
echo "║   Dostępne aktualizacje                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Show what is available
fp_count=$(flatpak remote-ls --user --updates 2>/dev/null | wc -l)
ostree_info=$(rpm-ostree upgrade --check 2>/dev/null || true)
ostree_available=0
if printf "%s\n" "$ostree_info" | grep -q "AvailableUpdate:"; then
    ostree_available=$(printf "%s\n" "$ostree_info" | grep -oP "^\s*Diff:\s*\K[0-9]+" | head -1 || echo "?")
fi

echo "  Flatpak aplikacje:  $fp_count aktualizacji"
echo "  System Fedora OS:   ${ostree_available} pakietów (wymaga restartu)"
echo ""
echo "Co chcesz zaktualizować?"
echo ""
echo "  1) Tylko aplikacje Flatpak   (bez restartu)"
echo "  2) Tylko system Fedora OS    (wymaga restartu)"
echo "  3) Wszystko                  (Flatpak + OS, restart)"
echo "  4) Anuluj"
echo ""
read -rp "Wybierz [1-4]: " choice

case "$choice" in
    1)
        echo ""
        echo "── Aktualizacja Flatpak ────────────────────"
        flatpak update --user -y
        echo ""
        echo "✅ Gotowe. Restart nie jest potrzebny."
        ;;
    2)
        echo ""
        echo "── Aktualizacja systemu (rpm-ostree) ───────"
        rpm-ostree upgrade
        echo ""
        echo "✅ Gotowe. Wymagany restart."
        echo ""
        read -rp "Uruchomić ponownie teraz? [t/N] " reboot_ans
        [[ "$reboot_ans" =~ ^[TtYy]$ ]] && systemctl reboot
        ;;
    3)
        echo ""
        echo "── Aktualizacja Flatpak ────────────────────"
        flatpak update --user -y
        echo ""
        echo "── Aktualizacja systemu (rpm-ostree) ───────"
        rpm-ostree upgrade
        echo ""
        echo "✅ Gotowe. Wymagany restart dla OS."
        echo ""
        read -rp "Uruchomić ponownie teraz? [t/N] " reboot_ans
        [[ "$reboot_ans" =~ ^[TtYy]$ ]] && systemctl reboot
        ;;
    4|"")
        echo "Anulowano."
        ;;
    *)
        echo "Nieznana opcja."
        ;;
esac

# Force Waybar to refresh
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.json"
pkill -SIGRTMIN+8 waybar 2>/dev/null || true

echo ""
read -rp "Naciśnij Enter aby zamknąć..." _
'

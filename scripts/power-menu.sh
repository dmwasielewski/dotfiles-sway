#!/bin/bash
# Power menu for waybar — uses rofi
set -euo pipefail

options="⏻  Shutdown
🔄  Reboot
😴  Suspend
❄️  Hibernate
🚪  Logout"

choice=$(printf '%s\n' "$options" | rofi -dmenu -i -p "Power" -theme-str 'window {width: 240px;}')

case "$choice" in
    *Shutdown*)  systemctl poweroff ;;
    *Reboot*)    systemctl reboot ;;
    *Suspend*)   systemctl suspend ;;
    *Hibernate*) systemctl hibernate ;;
    *Logout*)    swaymsg exit ;;
esac

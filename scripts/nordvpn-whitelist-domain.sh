#!/bin/bash
# Add a domain to NordVPN allowlist via rofi prompt
set -euo pipefail

domain=$(printf '' | rofi -dmenu -p "NordVPN — whitelist domain:" -theme-str 'window {width: 480px;}')

[[ -z "$domain" ]] && exit 0

if nordvpn allowlist add domain "$domain" 2>/dev/null || nordvpn whitelist add domain "$domain" 2>/dev/null; then
    notify-send "NordVPN" "✅ Whitelisted: $domain"
else
    notify-send -u critical "NordVPN" "❌ Failed to whitelist: $domain"
fi

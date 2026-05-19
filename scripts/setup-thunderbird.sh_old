#!/bin/bash
# setup-thunderbird.sh — applies Thunderbird profile config from dotfiles
# Run after first Thunderbird launch (profile must exist).
# Thunderbird is installed as Flatpak (org.mozilla.Thunderbird) by setup.sh.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
TB_CONFIG="$DOTFILES/thunderbird"
TB_BASE="$HOME/.var/app/org.mozilla.Thunderbird/.thunderbird"

# Find the default-esr profile
PROFILE=$(ls -d "$TB_BASE"/*.default-esr 2>/dev/null | head -1)

if [[ -z "$PROFILE" ]]; then
    echo "==> No Thunderbird profile found at $TB_BASE"
    echo "    Launch Thunderbird once to create a profile, then re-run this script."
    exit 0
fi

echo "==> Thunderbird profile: $(basename "$PROFILE")"

# Copy user.js
echo "==> Applying user.js..."
cp "$TB_CONFIG/user.js" "$PROFILE/user.js"
echo "    Preferences: read receipts, light mode, custom CSS"

# Copy CSS files
echo "==> Applying custom CSS..."
mkdir -p "$PROFILE/chrome"
cp "$TB_CONFIG/userChrome.css" "$PROFILE/chrome/userChrome.css"
cp "$TB_CONFIG/userContent.css" "$PROFILE/chrome/userContent.css"
echo "    Unread messages: cyan, folders: bold"

echo ""
echo "==> Done. Restart Thunderbird to apply."
echo ""
echo "    Installed extensions (install manually from Add-ons Manager):"
echo "      Modern Theme Green, Dark Reader, Owl, ThunderAI, Send Later 3,"
echo "      Quote Colors, ImportExportTools NG, Thunderbird Pro"

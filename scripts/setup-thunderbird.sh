#!/bin/bash
# setup-thunderbird.sh — applies Thunderbird profile config from dotfiles
# Run after first Thunderbird launch (profile must exist).
# Thunderbird is installed as a Flatpak by setup.sh; its app ID is discovered at
# runtime (Flathub rebased org.mozilla.Thunderbird -> org.mozilla.thunderbird_esr),
# so the per-variant data dir is never hardcoded.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
TB_CONFIG="$DOTFILES/thunderbird"

TB_ID="$("$DOTFILES/scripts/thunderbird-id.sh" 2>/dev/null || true)"
if [[ -z "$TB_ID" ]]; then
    echo "==> No Thunderbird flatpak installed. Install it first (setup.sh), then re-run."
    exit 0
fi
TB_BASE="$HOME/.var/app/$TB_ID/.thunderbird"

# Find the default-esr profile
PROFILE=$(ls -d "$TB_BASE"/*.default-esr 2>/dev/null | head -1)

if [[ -z "$PROFILE" ]]; then
    echo "==> No Thunderbird profile found at $TB_BASE"
    echo "    Launch Thunderbird once to create a profile, then re-run this script."
    exit 0
fi

echo "==> Thunderbird profile: $(basename "$PROFILE")"

backup_once() {
    local file="$1"
    if [[ -f "$file" && ! -f "${file}_old" ]]; then
        cp "$file" "${file}_old"
    fi
}

# Copy user.js
echo "==> Applying user.js..."
backup_once "$PROFILE/user.js"
cp "$TB_CONFIG/user.js" "$PROFILE/user.js"
echo "    Preferences: read receipts, light mode, custom CSS"

# Copy CSS files
echo "==> Applying custom CSS..."
mkdir -p "$PROFILE/chrome"
backup_once "$PROFILE/chrome/userChrome.css"
backup_once "$PROFILE/chrome/userContent.css"
cp "$TB_CONFIG/userChrome.css" "$PROFILE/chrome/userChrome.css"
cp "$TB_CONFIG/userContent.css" "$PROFILE/chrome/userContent.css"
echo "    Unread messages: terminal blue, folders: calm bold"

echo ""
echo "==> Done. Restart Thunderbird to apply."
echo ""
echo "    Installed extensions (install manually from Add-ons Manager):"
echo "      Modern Theme Green, Dark Reader, Owl, ThunderAI, Send Later 3,"
echo "      Quote Colors, ImportExportTools NG, Thunderbird Pro"

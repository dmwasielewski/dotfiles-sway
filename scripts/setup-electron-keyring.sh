#!/bin/bash
# Point Flatpak Electron apps at the GNOME keyring explicitly.
#
# Chromium chooses its secret-storage backend from the desktop environment, and
# Sway is not one it recognises. Electron then falls back to `basic_text`: secrets
# are "encrypted" with a key hardcoded into Chromium, i.e. effectively plaintext,
# and some apps (Claude Desktop) refuse to keep a sign-in at all. gnome-keyring is
# in the Fedora Sway Atomic base image and is unlocked by PAM at login, so the
# keyring itself is not the problem — the apps just never ask it. Measured
# 2026-10-29 from cookie-DB prefixes (v10 = basic_text, v11 = keyring):
#   Obsidian v10 (affected) · ChatGPT, Bitwarden v11 (fine, left alone)
#   VS Code: no cookies to measure; its GitHub sign-in uses Electron safeStorage,
#   the API Claude Desktop showed reporting basic_text with v11 cookies.
#
# The fix is per app, never a global XDG_CURRENT_DESKTOP override: that variable
# also routes xdg-desktop-portal to a backend. Claude Desktop (user-local, not a
# Flatpak) gets the same flag from the wrapper written by setup-claude-desktop.sh.
#
# Each app is configured only if it is installed; existing settings are kept.
set -euo pipefail

FLAG="--password-store=gnome-libsecret"
BACKEND="gnome-libsecret"

installed() { flatpak info "$1" >/dev/null 2>&1; }

# ── Obsidian — the Flathub launcher reads one extra argument per line from
#    $XDG_CONFIG_HOME/obsidian/user-flags.conf inside the sandbox.
OBSIDIAN_FLAGS="$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/user-flags.conf"
if installed md.obsidian.Obsidian; then
    mkdir -p "$(dirname "$OBSIDIAN_FLAGS")"
    if grep -qx -- "$FLAG" "$OBSIDIAN_FLAGS" 2>/dev/null; then
        echo "==> Obsidian: keyring flag already set"
    elif grep -q -- '--password-store=' "$OBSIDIAN_FLAGS" 2>/dev/null; then
        echo "!! Obsidian: $OBSIDIAN_FLAGS already names another --password-store — left unchanged"
    else
        printf '%s\n' "$FLAG" >> "$OBSIDIAN_FLAGS"
        echo "==> Obsidian: added $FLAG to $OBSIDIAN_FLAGS"
    fi
fi

# ── VS Code — reads permanent switches from ~/.vscode/argv.json (the Flatpak
#    shares the host $HOME). The file is JSONC with comments and a per-install
#    crash-reporter-id, so it is edited in place, never regenerated or symlinked.
ARGV="$HOME/.vscode/argv.json"
if installed com.visualstudio.code; then
    mkdir -p "$(dirname "$ARGV")"
    if grep -q '"password-store"' "$ARGV" 2>/dev/null; then
        echo "==> VS Code: password-store already set in $ARGV — left unchanged"
    elif grep -qE '^[[:space:]]*"[^"]+"[[:space:]]*:' "$ARGV" 2>/dev/null; then
        # At least one key follows, so a trailing comma after ours stays valid JSON.
        sed -i "0,/^[[:space:]]*{/s//{\n\t\"password-store\": \"$BACKEND\",/" "$ARGV"
        echo "==> VS Code: added \"password-store\": \"$BACKEND\" to $ARGV"
    else
        # Missing, or only comments: nothing to preserve. VS Code adds its own
        # crash-reporter-id on the next start.
        printf '{\n\t"password-store": "%s"\n}\n' "$BACKEND" > "$ARGV"
        echo "==> VS Code: wrote $ARGV"
    fi
fi

echo "   Restart the apps for this to take effect; an app that had stored secrets"
echo "   under basic_text may ask you to sign in once more."

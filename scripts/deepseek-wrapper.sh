#!/bin/bash
# Low-motion launcher for CodeWhale — the npm package formerly published as
# "deepseek-tui", renamed to "codewhale" at v0.8.x (the old package is now an
# empty deprecation stub with no binary). The original "deepseek" / "deepseek-tui"
# command names are kept as aliases so existing habits/scripts keep working.
#
# It sets NO_ANIMATIONS=1 and passes --no-mouse-capture to cut foot/Sway repaint
# flicker. The target binary is resolved on PATH (npm's global bin), so the only
# thing referenced is the tool's command name — not a hardcoded internal path,
# which is what silently broke this launcher when the package was renamed.
set -euo pipefail

name="$(basename "$0")"
case "$name" in
    *-tui) target="codewhale-tui" ;;
    *)     target="codewhale" ;;
esac

if ! command -v "$target" >/dev/null 2>&1; then
    echo "$name launcher: '$target' is not on PATH." >&2
    echo "Install it with:  npm install -g codewhale" >&2
    exit 127
fi

export NO_ANIMATIONS=1
exec "$target" --no-mouse-capture "$@"

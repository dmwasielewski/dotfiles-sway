#!/bin/bash
# Build the application-scoped GTK3 empty-target compatibility shim.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-stirling-runtime.sh"
mkdir -p "$HOME/.config/Stirling-PDF/pipeline/watchedFolders"
if [[ ! -x "$HOME/.local/opt/stirling-pdf/current/usr/bin/Stirling-PDF" ]]; then
    step_save STIRLING_PDF_RUNTIME pending
    echo 'Stirling PDF payload missing; run setup-stirling-pdf.sh first.'
    exit 1
fi
if ! command -v gcc >/dev/null; then
    step_save STIRLING_PDF_RUNTIME pending
    echo 'GTK compatibility build pending: gcc becomes available after packages.sh and reboot.'
    exit 0
fi
lib_dir="$HOME/.local/lib/stirling-pdf"
mkdir -p "$lib_dir"
tmp=$(mktemp "$lib_dir/.clipboard.XXXXXX")
# shellcheck disable=SC2016
add_exit_hook 'rm -f "$tmp"'
if ! gcc -Wall -Wextra -Werror -O2 -shared -fPIC \
    "$DOTFILES/scripts/native/stirling-clipboard.c" -ldl -o "$tmp"; then
    step_failed STIRLING_PDF_RUNTIME
    exit 1
fi
chmod 0755 "$tmp"
mv -f "$tmp" "$lib_dir/clipboard-compat.so"
# Install a regular wrapper, replacing the old managed binary symlink.
rm -f "$HOME/.local/bin/stirling-pdf"
install -m0755 "$DOTFILES/scripts/stirling-pdf-launcher.sh" "$HOME/.local/bin/stirling-pdf"
step_done STIRLING_PDF_RUNTIME
echo 'Stirling PDF GTK compatibility shim and launcher installed; restart the app.'

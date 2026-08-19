#!/bin/bash
# setup-zed.sh — install the official Zed editor (GUI) from its upstream GitHub
# release into ~/.local/opt (+ a ~/.local/bin/zed symlink and a .desktop entry).
#
# Why user-local and not Flatpak/rpm-ostree:
#   * The Flathub build (dev.zed.Zed) is an UNOFFICIAL community wrapper, not
#     supported by Zed Industries — we want the official upstream binary.
#   * Zed is not in Fedora's repos, so a user-local install is the right path on
#     Atomic: no root, no reboot, no rpm-ostree layer. This mirrors how nvim and
#     yazi are installed (see setup-neovim-config.sh / setup-yazi.sh).
#
# Zed is a GUI editor (Wayland/GPU), launched on demand — there is intentionally
# no autostart, no workspace assignment and no keybinding (user's decision). The
# terminal editor stays Neovim; $EDITOR is left untouched.
#
# The version is discovered (latest stable) at runtime unless ZED_VERSION is set —
# no hardcoded version. A pre-downloaded tarball can be supplied via ZED_TARBALL
# to avoid re-downloading (the asset is ~140 MB).
set -euo pipefail

REPO="zed-industries/zed"
OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
mkdir -p "$OPT_DIR" "$BIN_DIR" "$APP_DIR"

# Discover the latest stable tag. Capture the response fully before parsing —
# piping curl straight into `grep -m1` makes grep close the pipe early, which
# under `set -o pipefail` surfaces as a curl write error (exit 23).
VERSION="${ZED_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    latest_json="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
    VERSION="$(printf '%s' "$latest_json" | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
fi
[[ -z "$VERSION" ]] && { echo "ERROR: could not determine the latest Zed version"; exit 1; }

ASSET="zed-linux-x86_64.tar.gz"
URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
RELEASE_DIR="$OPT_DIR/zed-${VERSION#v}"

if [[ -x "$RELEASE_DIR/bin/zed" ]] || compgen -G "$RELEASE_DIR/*/bin/zed" >/dev/null; then
    echo "==> Zed $VERSION already installed in $RELEASE_DIR"
else
    echo "==> Installing Zed $VERSION ..."
    # Work under $HOME (some sandboxes block writing fetched files to /tmp).
    tmp="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/zed-dl.XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT

    if [[ -n "${ZED_TARBALL:-}" && -f "$ZED_TARBALL" ]]; then
        echo "==> Using pre-downloaded tarball: $ZED_TARBALL"
        cp "$ZED_TARBALL" "$tmp/zed.tar.gz"
    else
        for attempt in 1 2 3 4; do
            curl -fL -C - --retry 2 "$URL" -o "$tmp/zed.tar.gz" && break
            echo "   download attempt $attempt failed — retrying…"; sleep 2
        done
    fi

    tar -xzf "$tmp/zed.tar.gz" -C "$tmp"
    # Discover the extracted tree and the launcher dynamically — the upstream
    # tarball nests everything under a top dir (e.g. zed.app/), so don't assume
    # its name. The launcher is a wrapper script that resolves its own app dir,
    # so the whole tree must be kept together.
    launcher="$(find "$tmp" -mindepth 2 -type f -path '*/bin/zed' | head -1)"
    [[ -z "$launcher" ]] && { echo "ERROR: Zed launcher (bin/zed) not found in the archive"; exit 1; }
    app_root="$(dirname "$(dirname "$launcher")")"   # the dir containing bin/, share/, libexec/
    mkdir -p "$RELEASE_DIR"
    cp -a "$app_root/." "$RELEASE_DIR/"
fi

# Resolve the installed launcher (top dir name is upstream's, discovered above).
ZED_BIN="$(find "$RELEASE_DIR" -maxdepth 2 -type f -path '*/bin/zed' | head -1)"
[[ -z "$ZED_BIN" ]] && { echo "ERROR: installed Zed launcher not found under $RELEASE_DIR"; exit 1; }
ln -sfn "$ZED_BIN" "$BIN_DIR/zed"

# Install the bundled icon(s) so app launchers show Zed's real icon, discovering
# whatever sizes the tarball ships (no hardcoded size/path).
while IFS= read -r icon; do
    [[ -z "$icon" ]] && continue
    rel="${icon#*/share/icons/hicolor/}"      # e.g. 512x512/apps/zed.png
    dest="$ICON_BASE/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -f "$icon" "$dest"
done < <(find "$RELEASE_DIR" -path '*/share/icons/hicolor/*' -name 'zed*.png' 2>/dev/null)

# Desktop entry pointing at the stable symlink (GUI app — Terminal=false, real Exec).
cat > "$APP_DIR/dev.zed.Zed.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=Zed
GenericName=Code Editor
Comment=A high-performance, multiplayer code editor
Exec=$BIN_DIR/zed %U
Terminal=false
Categories=Development;IDE;TextEditor;
Icon=zed
Keywords=editor;code;developer;ide;text;
StartupNotify=true
StartupWMClass=dev.zed.Zed
MimeType=text/plain;inode/directory;
DESKTOP

echo "==> Linked $BIN_DIR/zed and wrote $APP_DIR/dev.zed.Zed.desktop"
"$BIN_DIR/zed" --version 2>/dev/null || echo "   (run 'zed --version' to verify; ensure ~/.local/bin is on PATH)"

#!/bin/bash
# setup-yazi.sh — install the yazi terminal file manager from its official GitHub
# release into ~/.local/opt (+ ~/.local/bin symlinks). yazi is NOT in Fedora's
# repos, so a user-local binary install is the right path on Atomic: no root, no
# reboot, no rpm-ostree layer. The version is discovered (latest) at runtime
# unless YAZI_VERSION is set — no hardcoded version.
set -euo pipefail

REPO="sxyazi/yazi"
OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$OPT_DIR" "$BIN_DIR"

VERSION="${YAZI_VERSION:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')}"
[[ -z "$VERSION" ]] && { echo "ERROR: could not determine the latest yazi version"; exit 1; }

ASSET="yazi-x86_64-unknown-linux-gnu.zip"
URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
RELEASE_DIR="$OPT_DIR/yazi-${VERSION#v}"

if [[ -x "$RELEASE_DIR/yazi" ]]; then
    echo "==> yazi $VERSION already installed in $RELEASE_DIR"
else
    echo "==> Installing yazi $VERSION ..."
    # Download under $HOME (some sandboxes block writing fetched files to /tmp).
    tmp="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/yazi-dl.XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT
    for attempt in 1 2 3 4; do
        curl -fL -C - --retry 2 "$URL" -o "$tmp/yazi.zip" && break
        echo "   download attempt $attempt failed — retrying…"; sleep 2
    done
    unzip -q "$tmp/yazi.zip" -d "$tmp"
    src="$(dirname "$(find "$tmp" -type f -name yazi | head -1)")"
    [[ -z "$src" ]] && { echo "ERROR: yazi binary not found in the archive"; exit 1; }
    mkdir -p "$RELEASE_DIR"
    cp "$src/yazi" "$RELEASE_DIR/"
    [[ -f "$src/ya" ]] && cp "$src/ya" "$RELEASE_DIR/"   # ya = yazi's package-manager CLI
    chmod +x "$RELEASE_DIR"/*
fi

ln -sfn "$RELEASE_DIR/yazi" "$BIN_DIR/yazi"
[[ -f "$RELEASE_DIR/ya" ]] && ln -sfn "$RELEASE_DIR/ya" "$BIN_DIR/ya"
echo "==> Linked into $BIN_DIR:"
"$BIN_DIR/yazi" --version 2>/dev/null || echo "   (run 'yazi --version' to verify; ensure ~/.local/bin is on PATH)"

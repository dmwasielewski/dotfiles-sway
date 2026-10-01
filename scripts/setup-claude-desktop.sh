#!/bin/bash
# Install Claude Desktop for the current user only.
#
# Anthropic ships this as a .deb and nothing else; there is no RPM and Fedora is
# not a supported target. That does not mean waiting: a .deb is an `ar` archive
# holding a tar, so the package can be unpacked into ~/.local/opt exactly the way
# setup-chatgpt.sh unpacks an RPM. Nothing is layered onto the ostree deployment
# — a third-party package's scriptlet failing there blocks every OS update, which
# is what the layered ChatGPT build did on 2026-09-02 — and nothing lives in a
# container, because a GUI application used daily belongs in the Fedora layer.
#
# All ten shared libraries the package declares are present in the base image, so
# the unpacked Electron tree runs against the host's own libraries.
set -euo pipefail

GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

REPO_BASEURL="https://downloads.claude.ai/claude-desktop/apt/stable"
DIST="stable"
COMPONENT="main"
ARCH="amd64"

OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MANIFEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-updates"
DL_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-dl"

PKG="claude-desktop"
PAYLOAD_LAUNCHER="usr/lib/$PKG/$PKG"

# ── Upstream metadata ──────────────────────────────────────────────────────────
# Three fetches that check each other: Release states the checksum of Packages,
# Packages states the checksum of the .deb, and the .deb is verified against it.
# A swapped file anywhere in that chain fails before anything is unpacked. The
# trust anchor is TLS to the vendor's host — the same anchor apt would use, since
# the signing key for a full OpenPGP check is not published anywhere we can reach
# without importing it into a keyring this read-only system has no room for.
_release() { curl -fsSL "$REPO_BASEURL/dists/$DIST/Release"; }

_packages() {                            # $1 = Release text
    local path sum body actual
    path="$COMPONENT/binary-$ARCH/Packages"
    body="$(curl -fsSL "$REPO_BASEURL/dists/$DIST/$path")" || return 1
    # Release lists every file under SHA256; take the line for exactly our path.
    sum="$(awk -v p="$path" '/^SHA256:/{s=1;next} /^[A-Za-z-]+:/{s=0}
           s && $3==p {print $1; exit}' <<< "$1")"
    if [[ -n "$sum" ]]; then
        actual="$(printf '%s\n' "$body" | sha256sum | awk '{print $1}')"
        [[ "$actual" == "$sum" ]] || {
            echo "ERROR: $path does not match the checksum in Release — refusing to continue." >&2
            return 1; }
    fi
    printf '%s\n' "$body"
}

# The newest version in the index, by version order rather than by file order.
upstream_version() {                     # $1 = Packages text
    grep '^Version:' <<< "$1" | awk '{print $2}' | sort -V | tail -1
}

# The stanza for one version, so location and checksum cannot come from a
# different build than the version we record.
_stanza() {                              # $1 = Packages text, $2 = version
    awk -v v="$2" 'BEGIN{RS=""} $0 ~ ("(^|\n)Version: " v "(\n|$)")' <<< "$1" | head -c 4000
}
field() { sed -n "s/^$2: //p" <<< "$1" | head -1; }   # $1 = stanza, $2 = field

if [[ "${1:-}" == "--print-latest-version" ]]; then
    REL="$(_release)" || { echo "ERROR: could not reach $REPO_BASEURL" >&2; exit 1; }
    PKGS="$(_packages "$REL")" || exit 1
    upstream_version "$PKGS"
    exit 0
fi

echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║        Claude Desktop — setup            ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "$OPT_DIR" "$BIN_DIR" "$APP_DIR" "$MANIFEST_DIR" "$DL_DIR"

echo "==> Reading upstream repository metadata ..."
REL="$(_release)" || { echo "ERROR: could not reach $REPO_BASEURL"; exit 1; }
PKGS="$(_packages "$REL")" || exit 1
VERSION="$(upstream_version "$PKGS")"
STANZA="$(_stanza "$PKGS" "$VERSION")"
LOCATION="$(field "$STANZA" Filename)"
SHA256="$(field "$STANZA" SHA256)"
[[ -n "$VERSION" && -n "$LOCATION" && -n "$SHA256" ]] || {
    echo "ERROR: the package index did not carry a version, filename and checksum"; exit 1; }
echo "    latest: $VERSION"

RELEASE_DIR="$OPT_DIR/$PKG-$VERSION"
LAUNCHER="$RELEASE_DIR/$PAYLOAD_LAUNCHER"

if [[ -x "$LAUNCHER" ]]; then
    echo "==> $PKG $VERSION already installed in $RELEASE_DIR"
else
    DEB="$DL_DIR/$(basename "$LOCATION")"
    if [[ -s "$DEB" ]] && printf '%s  %s\n' "$SHA256" "$DEB" | sha256sum -c --status; then
        echo "==> Reusing the verified package already downloaded: $DEB"
    else
        echo "==> Downloading $(basename "$LOCATION") (~170 MB) ..."
        curl -fL -C - --retry 3 -o "$DEB" "$REPO_BASEURL/$LOCATION"
        echo "==> Verifying checksum ..."
        printf '%s  %s\n' "$SHA256" "$DEB" | sha256sum -c --status || {
            echo "ERROR: sha256 does not match the package index — refusing to install."
            rm -f "$DEB"; exit 1; }
    fi
    echo "    checksum OK"

    echo "==> Unpacking into $RELEASE_DIR ..."
    rm -rf "$RELEASE_DIR.partial"
    mkdir -p "$RELEASE_DIR.partial"
    # ar splits the .deb into control/data/debian-binary; only data holds the tree.
    ( cd "$RELEASE_DIR.partial" && ar x "$DEB" && tar -xf data.tar.* && rm -f ./*.tar.* debian-binary )
    [[ -x "$RELEASE_DIR.partial/$PAYLOAD_LAUNCHER" ]] || {
        echo "ERROR: $PAYLOAD_LAUNCHER not found in the package — upstream changed its layout."
        rm -rf "$RELEASE_DIR.partial"; exit 1; }
    # Rename only once the tree is complete, so an interrupted unpack can never
    # leave a half-extracted directory that looks like a finished install.
    mv -T "$RELEASE_DIR.partial" "$RELEASE_DIR"
    rm -f "$DEB"                         # ~170 MB; the release dir is the artefact now
fi

ln -sfn "$LAUNCHER" "$BIN_DIR/$PKG"      # NOT `claude` — that name is the CLI

# Desktop entry: start from the one upstream ships and rewrite only the program
# name, so %U, the claude:// scheme handler and both Desktop Actions keep the
# arguments upstream gave them. (setup-chatgpt.sh replaces whole Exec lines; that
# would flatten this package's two actions into a plain launch.)
PACKAGED_DESKTOP="$(find "$RELEASE_DIR/usr/share/applications" -name '*.desktop' 2>/dev/null | head -1)"
ICON_SRC="$(find "$RELEASE_DIR/usr/share/icons" -name "$PKG.png" 2>/dev/null |
            sort -t/ -k7 -V | tail -1)"   # largest hicolor size available
if [[ -n "$PACKAGED_DESKTOP" ]]; then
    sed -e "s:^Exec=$PKG:Exec=$LAUNCHER:" \
        -e "s:^Icon=.*:Icon=${ICON_SRC:-$PKG}:" \
        "$PACKAGED_DESKTOP" > "$APP_DIR/$(basename "$PACKAGED_DESKTOP")"
    echo "==> Wrote $APP_DIR/$(basename "$PACKAGED_DESKTOP")"
else
    echo "!! no .desktop found in the package — the launcher entry was not written."
fi
command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APP_DIR" 2>/dev/null || true

# Never delete a tree something is still executing from. Asked through /proc
# rather than by matching command lines: on 2026-09-02 a pgrep pattern built from
# $HOME ("/home/damian/...") missed a process reporting "/var/home/damian/..." —
# the same directory by a different name, since /home is a symlink to /var/home
# here — and the prune deleted 1.4 GB out from under the running app.
dir_in_use() {                           # $1 = directory
    local dir exe
    dir="$(readlink -f "$1")"
    for exe in /proc/[0-9]*/exe; do
        [[ "$(readlink -f "$exe" 2>/dev/null)" == "$dir"/* ]] && return 0
    done
    return 1
}

while IFS= read -r old; do
    [[ "$old" == "$RELEASE_DIR" ]] && continue
    if dir_in_use "$old"; then
        echo "==> $old is still running — leaving it; it will go on the next run"
        continue
    fi
    echo "==> Removing superseded $old"
    rm -rf "$old"
done < <(find "$OPT_DIR" -maxdepth 1 -type d -name "$PKG-*" 2>/dev/null)

# Let the Waybar update module see new releases. The version does not come from
# GitHub, so the manifest names a probe command; lib-updates.sh dispatches on
# which field is present.
cat > "$MANIFEST_DIR/$PKG" << MANIFEST
name=$PKG
installed_version=$VERSION
version_probe=scripts/setup-claude-desktop.sh --print-latest-version
updater=scripts/setup-claude-desktop.sh
MANIFEST

echo ""
echo -e "${GREEN}✔ $PKG $VERSION installed in $RELEASE_DIR${NC}"
echo "   launcher: $BIN_DIR/$PKG   (ensure ~/.local/bin is on PATH)"
echo ""
echo "   The package ships chrome-sandbox without the setuid bit it would get from"
echo "   dpkg. This kernel allows unprivileged user namespaces, so Electron should"
echo "   use its namespace sandbox instead. If it refuses to start with a message"
echo "   about the SUID sandbox helper, say so rather than adding --no-sandbox:"
echo "   that turns the sandbox off, and it is worth deciding deliberately."

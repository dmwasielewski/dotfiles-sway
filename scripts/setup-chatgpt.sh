#!/bin/bash
# setup-chatgpt.sh — install the official ChatGPT desktop app (which also hosts
# Codex) user-local, from OpenAI's own RPM, WITHOUT layering it onto the OS.
#
# Why not rpm-ostree layering (which is what this script used to do):
# On 2026-09-01 upstream's %post started doing `mkdir -p /var/lib/chatgpt`.
# /var is READ-ONLY inside rpm-ostree's scriptlet sandbox — packages targeting
# ostree systems have to create their state via systemd-tmpfiles — and the
# scriptlet runs under `set -e`, so it aborted the transaction:
#
#   error: Running %post for chatgpt: bwrap(/bin/sh): Child process exited
#   with code 1
#   rpm-ostree(chatgpt.post): mkdir: cannot create directory
#   '/var/lib/chatgpt': Read-only file system
#
# An rpm-ostree transaction is atomic and covers the base tree together with
# every layered package, so one third-party scriptlet failing this way blocked
# ALL OS updates — Fedora's security updates included. The app is a
# self-contained Electron tree under /usr/lib/chatgpt with a relocatable
# launcher (`dirname $(readlink -f $0)`) and no absolute paths in its payload
# (checked), so it does not need to be part of the OS image at all.
#
# So: same official package, same signature check, unpacked into ~/.local/opt
# instead. Native on Fedora, no container, no root, no reboot, and the OS
# update path is left alone. Same shape as scripts/setup-yazi.sh.
#
# Nothing about the version is hardcoded: the version, the package filename and
# its checksum all come from the repository metadata at runtime.
#
#   setup-chatgpt.sh                          install/upgrade to the latest
#   setup-chatgpt.sh --print-latest-version   print the upstream version, exit
set -euo pipefail

REPO_BASEURL="https://persistent.oaistatic.com/codex-app-prod/linux/rpm/x86_64"

OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MANIFEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-updates"
DL_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-dl"

PKG="chatgpt"
# The payload root inside the RPM. Derived from the launcher symlink upstream
# ships (/usr/bin/chatgpt -> ../lib/chatgpt/codex-launcher) rather than assumed.
PAYLOAD_LAUNCHER="usr/lib/$PKG/codex-launcher"

# ── Upstream metadata (repodata — a 2.5 KB file, cheap enough to poll) ──────
# repomd.xml names the current primary.xml.gz; primary.xml carries the version,
# the package's location and its sha256. Reading all three from the same place
# means the download, the integrity check and the version we record can never
# disagree with each other.
_primary_xml() {
    local href
    href="$(curl -fsSL "$REPO_BASEURL/repodata/repomd.xml" \
            | sed -n 's:.*<location href="\(repodata/[^"]*primary\.xml\.gz\)".*:\1:p' | head -1)"
    [[ -n "$href" ]] || return 1
    curl -fsSL "$REPO_BASEURL/$href" | gunzip
}

upstream_version() {                   # $1 = primary.xml text
    printf '%s' "$1" | sed -n 's:.*<version epoch="[^"]*" ver="\([^"]*\)" rel="\([^"]*\)".*:\1-\2:p' | head -1
}
upstream_location() {                  # $1 = primary.xml text
    printf '%s' "$1" | sed -n 's:.*<location href="\([^"]*\)".*:\1:p' | head -1
}
upstream_sha256() {                    # $1 = primary.xml text
    printf '%s' "$1" | sed -n 's:.*<checksum type="sha256" pkgid="YES">\([a-f0-9]*\)<.*:\1:p' | head -1
}

# ── --print-latest-version: the update indicator's version probe ───────────
if [[ "${1:-}" == "--print-latest-version" ]]; then
    primary="$(_primary_xml)" || { echo "could not read repository metadata" >&2; exit 1; }
    ver="$(upstream_version "$primary")"
    [[ -n "$ver" ]] || { echo "could not parse the version from repository metadata" >&2; exit 1; }
    printf '%s\n' "$ver"
    exit 0
fi

# shellcheck source=scripts/lib-install.sh
source "${DOTFILES:-$HOME/dotfiles-sway}/scripts/lib-install.sh"
setup_logging "scripts/setup-chatgpt.sh"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   ChatGPT desktop (incl. Codex) — setup  ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "$OPT_DIR" "$BIN_DIR" "$APP_DIR" "$MANIFEST_DIR" "$DL_DIR"

echo "==> Reading upstream repository metadata ..."
PRIMARY="$(_primary_xml)" || { echo "ERROR: could not reach $REPO_BASEURL"; exit 1; }
VERSION="$(upstream_version "$PRIMARY")"
LOCATION="$(upstream_location "$PRIMARY")"
SHA256="$(upstream_sha256 "$PRIMARY")"
[[ -n "$VERSION" && -n "$LOCATION" && -n "$SHA256" ]] || {
    echo "ERROR: repository metadata did not contain a version, location and checksum"; exit 1; }
echo "    latest: $VERSION"

RELEASE_DIR="$OPT_DIR/$PKG-$VERSION"
LAUNCHER="$RELEASE_DIR/$PAYLOAD_LAUNCHER"

if [[ -x "$LAUNCHER" ]]; then
    echo "==> $PKG $VERSION already installed in $RELEASE_DIR"
else
    RPM="$DL_DIR/$(basename "$LOCATION")"
    if [[ -s "$RPM" ]] && printf '%s  %s\n' "$SHA256" "$RPM" | sha256sum -c --status; then
        echo "==> Reusing the verified package already downloaded: $RPM"
    else
        echo "==> Downloading $LOCATION (~440 MB) ..."
        curl -fL -C - --retry 3 -o "$RPM" "$REPO_BASEURL/$LOCATION"
        echo "==> Verifying checksum ..."
        printf '%s  %s\n' "$SHA256" "$RPM" | sha256sum -c --status || {
            echo "ERROR: sha256 does not match the repository metadata — refusing to install."
            rm -f "$RPM"; exit 1; }
    fi

    # Integrity check. Two independent things are verified:
    #
    #   1. the sha256 that repodata.xml (a separate HTTPS fetch) states for this
    #      package — so a corrupted or swapped download is caught above;
    #   2. rpm's own header and payload digests, plus the key ID the package is
    #      signed with, printed so a key rotation is visible instead of silent.
    #
    # What is deliberately NOT done is a full OpenPGP verification against the
    # signing key. Two reasons, both checked rather than assumed:
    #
    #   - rpm 6 refuses to create its transaction lock anywhere but the system
    #     dbpath ("can't create transaction lock ... Permission denied", even in
    #     a writable directory we own), and that dbpath is read-only on an ostree
    #     system — so a key cannot be imported into any keyring without root;
    #   - upstream ships the signing key ONLY inside the package's own %post
    #     scriptlet; there is no public key URL (/gpg, /gpg.key,
    #     /RPM-GPG-KEY-chatgpt all 404). A signature checked against a key that
    #     travelled inside the signed artefact proves internal consistency, not
    #     provenance: whoever could swap the package could swap the key with it.
    #
    # So the real trust anchor here is TLS to the vendor's host — which is also
    # what it was for the layered install, whose gpgcheck used that same
    # package-embedded key. Nothing weaker than before; the repodata checksum is
    # in fact one check more.
    echo "==> Verifying package integrity ..."
    # `|| true`: rpmkeys exits non-zero on NOKEY (the signing key is not in any
    # keyring, and per the note above it cannot be) — the digest lines below are
    # what this checks, so the exit code must not end the script under `set -e`.
    sig_out="$(rpmkeys -Kv "$RPM" 2>&1 || true)"
    if ! printf '%s\n' "$sig_out" | grep -q 'Header SHA256 digest: OK' ||
       ! printf '%s\n' "$sig_out" | grep -q 'Payload SHA256 digest: OK'; then
        echo "ERROR: rpm digests do not verify for $RPM — refusing to install."
        printf '%s\n' "$sig_out"; exit 1
    fi
    echo "    digests OK"
    echo "    signed with: $(printf '%s\n' "$sig_out" |
                             sed -n 's/.*signature, key ID \([0-9a-f]*\).*/\1/p' | head -1)"

    echo "==> Unpacking into $RELEASE_DIR ..."
    rm -rf "$RELEASE_DIR.partial"
    mkdir -p "$RELEASE_DIR.partial"
    ( cd "$RELEASE_DIR.partial" && rpm2cpio "$RPM" | cpio -idm --quiet )
    [[ -x "$RELEASE_DIR.partial/$PAYLOAD_LAUNCHER" ]] || {
        echo "ERROR: $PAYLOAD_LAUNCHER not found in the package — upstream changed its layout."
        rm -rf "$RELEASE_DIR.partial"; exit 1; }
    # Rename only once the tree is complete, so an interrupted unpack can never
    # leave a half-extracted directory that looks like a finished install.
    mv -T "$RELEASE_DIR.partial" "$RELEASE_DIR"
    rm -f "$RPM"                       # ~440 MB; the release dir is the artefact now
fi

ln -sfn "$LAUNCHER" "$BIN_DIR/$PKG"

# Desktop entry: start from the one upstream ships and rewrite only the two
# lines that assume a system-wide install, so the MIME handlers, categories and
# the codex:// scheme stay exactly as upstream defined them.
PACKAGED_DESKTOP="$RELEASE_DIR/usr/share/applications/$PKG.desktop"
ICON_SRC="$RELEASE_DIR/usr/share/pixmaps/$PKG.png"
if [[ -f "$PACKAGED_DESKTOP" ]]; then
    sed -e "s:^Exec=.*:Exec=$LAUNCHER %U:" \
        -e "s:^Icon=.*:Icon=$ICON_SRC:" \
        "$PACKAGED_DESKTOP" > "$APP_DIR/$PKG.desktop"
    echo "==> Wrote $APP_DIR/$PKG.desktop"
else
    echo "!! $PKG.desktop not found in the package — the app launcher entry was not written."
fi
command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APP_DIR" 2>/dev/null || true

# Keep only the release we just linked. Each unpacked tree is ~1.4 GB, so the
# yazi pattern of leaving old versions behind is not affordable here.
# Never delete a tree something is still executing from: this is a lazily-mapped
# Electron install (.pak files, app.asar, a zygote and a crash handler respawned
# from disk), not a single static binary like yazi's — pulling it out from under
# a running session breaks that session mid-use. The app autostarts on ws5, so
# an upgrade while it is open is the normal case, not the edge one.
while IFS= read -r old; do
    [[ "$old" == "$RELEASE_DIR" ]] && continue
    if pgrep -f "^$old/" >/dev/null 2>&1; then
        echo "==> $old is still running — leaving it; it will go on the next run"
        continue
    fi
    echo "==> Removing superseded $old"
    rm -rf "$old"
done < <(find "$OPT_DIR" -maxdepth 1 -type d -name "$PKG-*" 2>/dev/null)

# Update manifest, so the Waybar update app can see a new release. The version
# does not come from GitHub, so the manifest names a probe command instead of a
# repo; lib-updates.sh dispatches on which field is present.
cat > "$MANIFEST_DIR/$PKG" << MANIFEST
name=$PKG
installed_version=$VERSION
version_probe=scripts/setup-chatgpt.sh --print-latest-version
updater=scripts/setup-chatgpt.sh
MANIFEST

echo ""
echo -e "${GREEN}✔ $PKG $VERSION installed in $RELEASE_DIR${NC}"
echo "   launcher: $BIN_DIR/$PKG   (ensure ~/.local/bin is on PATH)"

# The layered copy, if any, must go — it is what blocks `rpm-ostree upgrade`.
# Removing it changes the OS deployment, so it needs root and a reboot: report
# it, do not do it silently from a setup script.
if rpm -q "$PKG" >/dev/null 2>&1; then
    echo ""
    echo -e "${YELLOW}!! $PKG is ALSO layered onto the OS image ($(rpm -q --qf '%{VERSION}-%{RELEASE}' "$PKG")).${NC}"
    echo -e "${YELLOW}   While it is layered, every 'rpm-ostree upgrade' aborts on its %post${NC}"
    echo -e "${YELLOW}   scriptlet and no OS update — security updates included — can install.${NC}"
    echo -e "${YELLOW}   Remove it and reboot:${NC}"
    echo ""
    echo -e "${YELLOW}     sudo rpm-ostree uninstall $PKG && systemctl reboot${NC}"
    echo ""
    echo -e "${YELLOW}   Until that reboot, /usr/bin/$PKG still points at the layered copy.${NC}"
fi

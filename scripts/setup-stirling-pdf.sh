#!/bin/bash
# Official desktop RPM, unpacked user-local on Fedora Atomic; no scriptlets/root.
# Offline inputs must include release metadata with the upstream SHA256 digest.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-stirling-pdf.sh"
step_save STIRLING_PDF_INSTALLED running
# Used by deferred exit hook.
# shellcheck disable=SC2034
stirling_done=0
# shellcheck disable=SC2016
add_exit_hook 'if [[ "$stirling_done" != 1 ]]; then step_failed STIRLING_PDF_INSTALLED; fi'
[[ "$(uname -m)" == x86_64 ]] || { echo 'ERROR: upstream desktop package requires x86_64'; exit 1; }
for tool in curl python3 rpm rpm2cpio cpio sha256sum; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$cache" "$HOME/.local/opt" "$HOME/.local/bin"
tmp="$(mktemp -d "$cache/stirling-pdf.XXXXXX")"
# shellcheck disable=SC2016
add_exit_hook 'rm -rf "$tmp"'
if [[ -n "${STIRLING_RELEASE_JSON:-}" ]]; then
    cp "$STIRLING_RELEASE_JSON" "$tmp/release.json"
else
    curl -fsSL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 \
        https://api.github.com/repos/Stirling-Tools/Stirling-PDF/releases/latest -o "$tmp/release.json"
fi
python3 - "$tmp/release.json" > "$tmp/metadata" <<'PY'
import json, re, sys
release = json.load(open(sys.argv[1]))
tag = release['tag_name']
if not re.fullmatch(r'v?[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.]+)?', tag):
    raise SystemExit('ERROR: invalid release version')
asset = next(a for a in release['assets'] if a['name'] == 'Stirling-PDF-linux-x86_64.rpm')
digest = asset.get('digest') or ''
if not re.fullmatch(r'sha256:[a-f0-9]{64}', digest):
    raise SystemExit('ERROR: upstream SHA256 digest missing; refusing unverified installation')
url = asset['browser_download_url']
if not url.startswith('https://github.com/Stirling-Tools/Stirling-PDF/releases/download/'):
    raise SystemExit('ERROR: unexpected release download URL')
print(tag, url, digest[7:], sep='\n')
PY
mapfile -t metadata < "$tmp/metadata"
version="${metadata[0]}"
release_dir="$HOME/.local/opt/stirling-pdf-${version#v}"
if [[ -n "${STIRLING_RPM:-}" ]]; then
    cp "$STIRLING_RPM" "$tmp/package.rpm"
else
    curl -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 \
        "${metadata[1]}" -o "$tmp/package.rpm"
fi
printf '%s  %s\n' "${metadata[2]}" "$tmp/package.rpm" | sha256sum -c -
[[ "$(rpm -qp --qf '%{VERSION}' "$tmp/package.rpm")" == "${version#v}" ]] || {
    echo 'ERROR: RPM version differs from release metadata'; exit 1;
}
mkdir "$tmp/payload"
(cd "$tmp/payload"; rpm2cpio "$tmp/package.rpm" | cpio -idm --quiet --no-absolute-filenames)
payload="$tmp/payload"
test -x "$payload/usr/bin/Stirling-PDF"
test -x "$payload/usr/lib/Stirling PDF/runtime/jre/bin/java"
compgen -G "$payload/usr/lib/Stirling PDF/libs/stirling-pdf-*.jar" >/dev/null
# Keep usr/bin and usr/lib together: Tauri resolves resources relative to its binary.
if [[ ! -d "$release_dir" ]]; then
    mv "$payload" "$release_dir"
else
    test -x "$release_dir/usr/bin/Stirling-PDF"
    test -x "$release_dir/usr/lib/Stirling PDF/runtime/jre/bin/java"
    echo "==> Stirling-PDF $version already installed"
fi
mkdir -p "$HOME/.local/opt/stirling-pdf"
ln -sfn "$release_dir" "$HOME/.local/opt/stirling-pdf/current"
# Replace only the managed launcher symlink/file; install must not follow the old link.
rm -f "$HOME/.local/bin/stirling-pdf"
install -m 0755 "$DOTFILES/scripts/stirling-pdf-launcher.sh" "$HOME/.local/bin/stirling-pdf"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data/applications" "$data/icons/hicolor" "$data/dotfiles-updates"
cp -a "$release_dir/usr/share/icons/hicolor/." "$data/icons/hicolor/"
cat > "$data/applications/stirling-pdf.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Stirling PDF
Comment=Edit, merge, split and convert PDF documents locally
Exec="$HOME/.local/bin/stirling-pdf" %U
Icon=Stirling-PDF
Terminal=false
Categories=Office;
MimeType=application/pdf;
StartupNotify=true
DESKTOP
cat > "$data/dotfiles-updates/stirling-pdf" <<MANIFEST
name=Stirling PDF
repo=Stirling-Tools/Stirling-PDF
installed_version=$version
updater=scripts/setup-stirling-pdf.sh
MANIFEST
if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$data/applications"
fi
bash "$DOTFILES/scripts/setup-stirling-runtime.sh"
step_done STIRLING_PDF_INSTALLED
# shellcheck disable=SC2034
stirling_done=1
echo "==> Installed Stirling-PDF $version. Open Stirling PDF from the app menu."
echo '    First launch: Continue without signing in for Local Only mode.'

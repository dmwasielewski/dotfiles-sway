#!/bin/bash
# Native Google Drive mount backend; account authorization is a separate step.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
latest_version() {
    local response
    response="$(curl -fsSL --connect-timeout 5 --max-time 15 https://downloads.rclone.org/version.txt)"
    [[ "$response" =~ ^rclone\ v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}
if [[ "${1:-}" == --print-latest-version ]]; then latest_version; exit; fi
source "$DOTFILES/scripts/lib-install.sh"
setup_logging setup-google-drive.sh
step_failed GOOGLE_DRIVE_SETUP
command -v fusermount3 >/dev/null || { echo 'Install host fuse3 with packages.sh and reboot first.'; exit 1; }
[[ -r /dev/fuse && -w /dev/fuse ]] || { echo 'Host /dev/fuse is not accessible.'; exit 1; }
case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo 'Unsupported Rclone architecture'; exit 1 ;;
esac
version="$(latest_version)"
root="$HOME/.local/opt/rclone"
mkdir -p "$root" "$HOME/.local/bin"
tmp="$(mktemp -d "$root/download.XXXXXX")"
# lib-install has its own logging EXIT hook; preserve it.
add_exit_hook 'rm -rf -- "$tmp"'
asset="rclone-v${version}-linux-${arch}.zip"
curl -fsSL --retry 2 --connect-timeout 10 --max-time 180 \
    "https://downloads.rclone.org/v${version}/$asset" -o "$tmp/$asset"
curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
    "https://downloads.rclone.org/v${version}/SHA256SUMS" -o "$tmp/SHA256SUMS"
# Extract ONLY the binary after matching its exact SHA256 entry. The checksum
# arrives over upstream TLS; this is not a claim of OpenPGP verification.
python3 - "$tmp" "$asset" <<'PY'
import hashlib, pathlib, re, sys, zipfile
folder, asset = pathlib.Path(sys.argv[1]), sys.argv[2]
entries = re.findall(r'^([0-9a-f]{64})\s+\*?' + re.escape(asset) + r'\s*$',
                     (folder / 'SHA256SUMS').read_text(), re.M)
if len(entries) != 1 or hashlib.sha256((folder / asset).read_bytes()).hexdigest() != entries[0]:
    raise SystemExit('Rclone SHA256 mismatch or missing checksum; refusing installation')
with zipfile.ZipFile(folder / asset) as archive:
    (folder / 'rclone').write_bytes(archive.read(asset[:-4] + '/rclone'))
(folder / 'rclone').chmod(0o755)
PY
"$tmp/rclone" version
release="$(mktemp -d "$root/$version.XXXXXX")"
install -m 755 "$tmp/rclone" "$release/rclone"
ln -sfn "$release" "$root/current"
# The backend stays private to the desktop mount, rather than becoming a dev
# tool in just one of the two development containers.
mkdir -p "$HOME/.config/google-drive" "$HOME/.config/systemd/user" \
    "$HOME/.local/share/applications" "$HOME/.local/share/dotfiles-updates" \
    "$HOME/GoogleDrive"
chmod 700 "$HOME/.config/google-drive"
ln -sfn "$DOTFILES/scripts/google-drive-waybar.py" "$HOME/.local/bin/google-drive-waybar"
ln -sfn "$DOTFILES/systemd/user/google-drive.service" "$HOME/.config/systemd/user/google-drive.service"
ln -sfn "$DOTFILES/applications/google-drive.desktop" "$HOME/.local/share/applications/google-drive.desktop"
systemctl --user daemon-reload
update-desktop-database "$HOME/.local/share/applications"
cat > "$HOME/.local/share/dotfiles-updates/rclone-google-drive" <<MANIFEST
name=Rclone (Google Drive)
installed_version=$version
version_probe=scripts/setup-google-drive.sh --print-latest-version
updater=scripts/setup-google-drive.sh
MANIFEST
step_done GOOGLE_DRIVE_SETUP
echo 'Installed Google Drive files on demand. Click its Waybar icon to connect your account.'
echo 'Account credentials and cached/pending files stay outside git; updates never erase them.'
print_state_summary

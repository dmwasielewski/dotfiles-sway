#!/bin/bash
# Native user-local client + GUI. Distrobox only supplies signed Fedora RPMs;
# neither the GUI nor the sync process runs in a container.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
CONTAINER=onedrive
GUI_REPO=bpozdena/OneDriveGUI

latest_gui() {
    local url
    url="$(curl -fsSL --retry 2 -o /dev/null -w '%{url_effective}' \
        "https://github.com/$GUI_REPO/releases/latest")" || return 1
    [[ "$url" =~ /releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}
case "${1:-}" in
    --print-latest-gui-version) latest_gui; exit ;;
    --print-latest-version)
        distrobox enter --name "$CONTAINER" --no-tty -- \
            dnf -q repoquery --latest-limit=1 --queryformat '%{version}' onedrive
        exit ;;
esac

source "$DOTFILES/scripts/lib-install.sh"
setup_logging setup-onedrive.sh
step_failed ONEDRIVE_SETUP  # remains failed if any required command aborts
[[ "$(uname -m)" == x86_64 ]] || { echo 'OneDriveGUI installer supports x86_64 only'; exit 1; }
command -v distrobox >/dev/null || { echo 'Run packages.sh and reboot first (distrobox missing)'; exit 1; }
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/distrobox"
if ! podman container exists "$CONTAINER"; then
    FEDORA_VERSION="$(. /etc/os-release; printf '%s' "$VERSION_ID")"
    distrobox create --yes --name "$CONTAINER" \
        --image "registry.fedoraproject.org/fedora-toolbox:$FEDORA_VERSION"
fi
# sudo here is inside the rootless container, never on the Atomic host.
distrobox enter --name "$CONTAINER" --no-tty -- sudo dnf install -y onedrive
distrobox enter --name "$CONTAINER" --no-tty -- sudo dnf upgrade -y onedrive ldc-libs
CLIENT_VERSION="$(distrobox enter --name "$CONTAINER" --no-tty -- /usr/bin/onedrive --version)"
CLIENT_VERSION="${CLIENT_VERSION##*v}"
python3 - "$CLIENT_VERSION" <<'PY'
import sys
assert tuple(map(int, sys.argv[1].split('.'))) >= (2, 5, 11), 'OneDriveGUI requires client >= 2.5.11'
PY
CLIENT_ROOT="$HOME/.local/opt/onedrive-client"
mkdir -p "$CLIENT_ROOT" "$HOME/.local/bin"
CLIENT_DIR="$(mktemp -d "$CLIENT_ROOT/$CLIENT_VERSION.XXXXXX")"
mkdir -p "$CLIENT_DIR/lib"
distrobox enter --name "$CONTAINER" --no-tty -- bash -c '
    set -euo pipefail
    cp /usr/bin/onedrive "$1/onedrive"
    cp -L /usr/lib64/libphobos2-ldc-shared.so.* /usr/lib64/libdruntime-ldc-shared.so.* "$1/lib/"
' _ "$CLIENT_DIR"
# Validate against HOST libraries before switching to this release.
env -u LD_PRELOAD LD_LIBRARY_PATH="$CLIENT_DIR/lib" "$CLIENT_DIR/onedrive" --version
ln -sfn "$CLIENT_DIR" "$CLIENT_ROOT/current"
ln -sfn "$DOTFILES/scripts/onedrive-wrapper.sh" "$HOME/.local/bin/onedrive"

GUI_VERSION="$(latest_gui)"
GUI_ROOT="$HOME/.local/opt/onedrive-gui"
GUI_DIR="$GUI_ROOT/$GUI_VERSION"
if [[ ! -x "$GUI_DIR/AppRun" ]]; then
    mkdir -p "$GUI_ROOT"
    DOWNLOAD_DIR="$(mktemp -d "$GUI_ROOT/download.XXXXXX")"
    add_exit_hook 'rm -rf "$DOWNLOAD_DIR"'
    curl -fL --retry 2 "https://github.com/$GUI_REPO/releases/download/v$GUI_VERSION/OneDriveGUI-$GUI_VERSION-x86_64.AppImage" \
        -o "$DOWNLOAD_DIR/OneDriveGUI.AppImage"
    chmod +x "$DOWNLOAD_DIR/OneDriveGUI.AppImage"
    (cd "$DOWNLOAD_DIR"; ./OneDriveGUI.AppImage --appimage-extract >/dev/null)
    [[ -x "$DOWNLOAD_DIR/squashfs-root/AppRun" ]]
    mv "$DOWNLOAD_DIR/squashfs-root" "$GUI_DIR"
fi
ln -sfn "$GUI_DIR" "$GUI_ROOT/current"
ln -sfn "$DOTFILES/scripts/onedrive-gui.sh" "$HOME/.local/bin/onedrive-gui"
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/dotfiles-updates"
ln -sfn "$DOTFILES/applications/OneDriveGUI.desktop" "$HOME/.local/share/applications/OneDriveGUI.desktop"
update-desktop-database "$HOME/.local/share/applications"
cat > "$HOME/.local/share/dotfiles-updates/onedrive-client" <<MANIFEST
name=OneDrive Client
installed_version=$CLIENT_VERSION
version_probe=scripts/setup-onedrive.sh --print-latest-version
updater=scripts/setup-onedrive.sh
MANIFEST
cat > "$HOME/.local/share/dotfiles-updates/onedrive-gui" <<MANIFEST
name=OneDriveGUI
installed_version=$GUI_VERSION
version_probe=scripts/setup-onedrive.sh --print-latest-gui-version
updater=scripts/setup-onedrive.sh
MANIFEST
step_done ONEDRIVE_SETUP
if [[ ! -s "$HOME/.config/onedrive-gui/profiles" ]]; then
    step_save ONEDRIVE_LOGIN pending
fi
echo 'OneDrive installed. Super+D → OneDriveGUI → create profile → Microsoft login.'
echo 'Choose ~/OneDrive, then enable Auto-sync on GUI startup in profile settings.'
echo 'Microsoft login and profile settings stay private, outside git.'
print_state_summary

#!/bin/bash
# Install native on-demand OneDrive access, without layering a third-party RPM.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
CONTAINER=onedrive
case "${1:-}" in
    --print-latest-version)
        distrobox enter --name "$CONTAINER" --no-tty -- \
            dnf -q repoquery --latest-limit=1 --queryformat '%{version}' onedriver
        exit ;;
esac
source "$DOTFILES/scripts/lib-install.sh"
setup_logging setup-onedriver.sh
step_failed ONEDRIVER_SETUP
command -v distrobox >/dev/null || { echo 'Run packages.sh and reboot first'; exit 1; }
command -v fusermount3 >/dev/null || { echo 'Host fuse3/fusermount3 is required'; exit 1; }
[[ -r /dev/fuse && -w /dev/fuse ]] || { echo 'Host /dev/fuse is not accessible'; exit 1; }
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/distrobox"
if ! podman container exists "$CONTAINER"; then
    FEDORA_VERSION="$(. /etc/os-release; printf '%s' "$VERSION_ID")"
    distrobox create --yes --name "$CONTAINER" \
        --image "registry.fedoraproject.org/fedora-toolbox:$FEDORA_VERSION"
fi
# These privileged package commands run ONLY inside the rootless container.
distrobox enter --name "$CONTAINER" --no-tty -- sudo dnf copr enable -y jstaf/onedriver
distrobox enter --name "$CONTAINER" --no-tty -- sudo dnf install -y onedriver
distrobox enter --name "$CONTAINER" --no-tty -- sudo dnf upgrade -y onedriver
VERSION="$(distrobox enter --name "$CONTAINER" --no-tty -- rpm -q --qf '%{VERSION}' onedriver)"
ROOT="$HOME/.local/opt/onedriver"
mkdir -p "$ROOT" "$HOME/.local/bin"
RELEASE_DIR="$(mktemp -d "$ROOT/$VERSION.XXXXXX")"
distrobox enter --name "$CONTAINER" --no-tty -- bash -c '
    set -euo pipefail
    cp /usr/bin/onedriver /usr/bin/onedriver-launcher "$1/"
    cp /usr/share/icons/onedriver/onedriver.svg "$1/"
' _ "$RELEASE_DIR"
# Both binaries must load all their dependencies against the HOST libraries.
"$RELEASE_DIR/onedriver" --version
"$RELEASE_DIR/onedriver-launcher" --version
ln -sfn "$RELEASE_DIR" "$ROOT/current"
ln -sfn "$ROOT/current/onedriver" "$HOME/.local/bin/onedriver"
ln -sfn "$ROOT/current/onedriver-launcher" "$HOME/.local/bin/onedriver-launcher"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/share/applications" \
    "$HOME/.local/share/icons/hicolor/scalable/apps" "$HOME/.local/share/dotfiles-updates"
ln -sfn "$DOTFILES/systemd/user/onedriver@.service" "$HOME/.config/systemd/user/onedriver@.service"
ln -sfn "$DOTFILES/applications/onedriver-launcher.desktop" "$HOME/.local/share/applications/onedriver-launcher.desktop"
ln -sfn "$ROOT/current/onedriver.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/onedriver.svg"
ln -sf "$DOTFILES/scripts/onedrive-waybar.py" "$HOME/.local/bin/onedrive-waybar"
mkdir -p "$HOME/OneDrive"
systemctl --user daemon-reload
# A successful replacement retires only repo-managed old launchers/manifests.
# Old payloads, Microsoft tokens/config and downloaded files are preserved.
for entry in "$HOME/.local/bin/onedrive" "$HOME/.local/bin/onedrive-gui" \
             "$HOME/.local/share/applications/OneDriveGUI.desktop"; do
    if [[ -L "$entry" && "$(readlink "$entry")" == "$DOTFILES/"* ]]; then
        rm "$entry"
    fi
done
for manifest in onedrive-client onedrive-gui; do
    file="$HOME/.local/share/dotfiles-updates/$manifest"
    if [[ -f "$file" ]] && grep -Fxq 'updater=scripts/setup-onedrive.sh' "$file"; then
        rm "$file"
    fi
done
# Disable an old GUI-generated autostart entry without deleting its contents.
if [[ -f "$HOME/.config/autostart/OneDriveGUI.desktop" ]]; then
    mv "$HOME/.config/autostart/OneDriveGUI.desktop" \
        "$HOME/.config/autostart/OneDriveGUI.desktop.disabled-$(date +%s)"
fi
update-desktop-database "$HOME/.local/share/applications"
cat > "$HOME/.local/share/dotfiles-updates/onedriver" <<MANIFEST
name=Onedriver
installed_version=$VERSION
version_probe=scripts/setup-onedriver.sh --print-latest-version
updater=scripts/setup-onedriver.sh
MANIFEST
step_done ONEDRIVER_SETUP
step_skip ONEDRIVE_SETUP
echo 'Installed onedriver. Super+D → Onedriver → + → select ~/OneDrive → Microsoft login.'
echo 'Use the gear beside the drive → Start drive on login for automatic mounting.'
echo 'Cloud contents are fetched when accessed; cache and tokens stay outside git.'
print_state_summary

#!/bin/bash
# setup-whispering-open.sh — install Whispering Open from the latest GitHub release

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-whispering-open.sh"

REPO="${WHISPERING_OPEN_REPO:-dmwasielewski/whispering-open}"
INSTALL_DIR="${WHISPERING_OPEN_INSTALL_DIR:-$HOME/.local/opt/whispering-open}"
BIN_LINK="$HOME/.local/bin/whispering-open"
ASSET_REGEX="${WHISPERING_OPEN_ASSET_REGEX:-linux|x86_64|amd64|appimage|rpm|tar|zip}"

echo ""
echo -e "${BOLD}${CYAN}==> Whispering Open — GitHub release setup${NC}"
echo ""
echo "Repository: $REPO"
echo "Install dir: $INSTALL_DIR"

if [[ -x "$BIN_LINK" ]]; then
    echo "==> Whispering Open already installed at $BIN_LINK — skipping download."
    step_done "WHISPERING_OPEN_INSTALLED"
    print_state_summary
    exit 0
fi

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1" >&2
        return 1
    fi
}

pick_release_asset() {
    python3 - "$ASSET_REGEX" "$1" <<'PY'
import json
import re
import sys

pattern = re.compile(sys.argv[1], re.I)
with open(sys.argv[2], encoding="utf-8") as handle:
    data = json.load(handle)
assets = data.get("assets", [])

priority = [
    re.compile(r"appimage$", re.I),
    re.compile(r"\.tar\.(gz|xz|bz2)$", re.I),
    re.compile(r"\.tgz$", re.I),
    re.compile(r"\.zip$", re.I),
    re.compile(r"\.rpm$", re.I),
]

matches = [
    asset for asset in assets
    if pattern.search(asset.get("name", "")) or pattern.search(asset.get("browser_download_url", ""))
]

for rule in priority:
    for asset in matches:
        name = asset.get("name", "")
        if rule.search(name):
            print(asset.get("browser_download_url", ""))
            sys.exit(0)

if matches:
    print(matches[0].get("browser_download_url", ""))
    sys.exit(0)

sys.exit(1)
PY
}

find_binary() {
    local root="$1"
    find "$root" -type f -perm -111 \
        \( -iname 'whispering-open' -o -iname 'whispering' -o -iname 'Whispering*.AppImage' -o -iname '*.AppImage' \) \
        | sort | head -n1
}

install_asset() {
    local asset="$1"
    local workdir="$2"
    local binary=""

    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" "$HOME/.local/bin"

    case "$asset" in
        *.AppImage|*.appimage)
            install -m 0755 "$asset" "$INSTALL_DIR/whispering-open.AppImage"
            binary="$INSTALL_DIR/whispering-open.AppImage"
            ;;
        *.rpm)
            require_tool rpm2cpio
            require_tool cpio
            mkdir -p "$INSTALL_DIR/root"
            (cd "$INSTALL_DIR/root" && rpm2cpio "$asset" | cpio -idm >/dev/null 2>&1)
            binary="$(find_binary "$INSTALL_DIR/root")"
            ;;
        *.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
            mkdir -p "$INSTALL_DIR/root"
            tar -xf "$asset" -C "$INSTALL_DIR/root"
            binary="$(find_binary "$INSTALL_DIR/root")"
            ;;
        *.zip)
            require_tool unzip
            mkdir -p "$INSTALL_DIR/root"
            unzip -oq "$asset" -d "$INSTALL_DIR/root"
            binary="$(find_binary "$INSTALL_DIR/root")"
            ;;
        *)
            echo "Unsupported release asset: $asset" >&2
            return 1
            ;;
    esac

    if [[ -z "$binary" || ! -x "$binary" ]]; then
        echo "Could not find executable Whispering Open binary after unpacking $asset" >&2
        return 1
    fi

    chmod +x "$binary"
    printf '%s\n' "$binary" > "$INSTALL_DIR/current-binary"
    # Launcher must set the WebKitGTK workaround env on Fedora Sway, otherwise the
    # app shows a blank/white window. A bare symlink to the binary skips this and
    # regresses every reinstall — see whispering-open AI_ERRORS.md. Write a wrapper
    # that exports the env and execs the recorded binary (resolved at runtime so it
    # survives version upgrades).
    cat > "$BIN_LINK" <<WRAP
#!/bin/bash
export GDK_BACKEND=x11
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export LIBGL_ALWAYS_SOFTWARE=1
exec "\$(cat "$INSTALL_DIR/current-binary")" "\$@"
WRAP
    chmod +x "$BIN_LINK"
    printf '%s\n' "$REPO" > "$INSTALL_DIR/source-repo"
    printf '%s\n' "$(basename "$asset")" > "$INSTALL_DIR/source-asset"
    echo "==> Installed Whispering Open binary: $binary"
}

run_install() {
    require_tool curl
    require_tool python3

    local api_url="https://api.github.com/repos/${REPO}/releases/latest"
    local workdir asset_url asset_path

    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' RETURN

    echo "==> Fetching latest release metadata..."
    if ! curl -fsSL "$api_url" -o "$workdir/release.json"; then
        echo "Could not fetch latest release from $api_url" >&2
        return 1
    fi

    if ! asset_url="$(pick_release_asset "$workdir/release.json")" || [[ -z "$asset_url" ]]; then
        echo "No suitable Linux release asset found for $REPO" >&2
        echo "Override with WHISPERING_OPEN_ASSET_REGEX or WHISPERING_OPEN_REPO if needed." >&2
        return 1
    fi

    asset_path="$workdir/${asset_url##*/}"
    echo "==> Downloading $asset_url"
    curl -fL "$asset_url" -o "$asset_path"

    install_asset "$asset_path" "$workdir"
}

run_step "WHISPERING_OPEN_INSTALLED" "Installing Whispering Open from GitHub release" run_install

echo ""
echo "Launch with: whispering-open"
echo "Launcher:    Mod+D -> Whispering Open"
echo ""
print_state_summary

#!/bin/bash
# setup-neovim-config.sh — latest pinned Neovim binary + Chris Titus Tech config

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
if [[ -f "$DOTFILES/scripts/lib-install.sh" ]]; then
    source "$DOTFILES/scripts/lib-install.sh"
    setup_logging "scripts/setup-neovim-config.sh"
fi

NVIM_VERSION="${NVIM_VERSION:-v0.12.1}"
NVIM_ARCHIVE="nvim-linux-x86_64.tar.gz"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_ARCHIVE}"
NVIM_OPT_DIR="$HOME/.local/opt"
NVIM_INSTALL_DIR="$NVIM_OPT_DIR/nvim-linux-x86_64"
NVIM_RELEASE_DIR="$NVIM_OPT_DIR/nvim-linux-x86_64-${NVIM_VERSION#v}"
NVIM_BIN="$HOME/.local/bin/nvim"
CTT_REPO_DIR="$DOTFILES/nvim/christitustech"
CTT_CONFIG_DIR="$CTT_REPO_DIR/titus-kickstart"
NVIM_CONFIG="$HOME/.config/nvim"

echo "==> Setting up Neovim ${NVIM_VERSION} with Chris Titus Tech config..."

if [[ ! -d "$CTT_REPO_DIR/.git" ]] && [[ ! -f "$CTT_REPO_DIR/.git" ]]; then
    echo "==> Initialising ChrisTitusTech/neovim submodule..."
    git -C "$DOTFILES" submodule update --init --recursive nvim/christitustech
fi

if [[ ! -f "$CTT_CONFIG_DIR/init.lua" ]]; then
    echo "ERROR: Chris Titus Tech Neovim config missing: $CTT_CONFIG_DIR/init.lua"
    exit 1
fi

mkdir -p "$HOME/.local/bin" "$NVIM_OPT_DIR" "$HOME/.config" "$HOME/.vim/undodir" "$HOME/.scripts"

installed_version=""
installed_from_install_dir=0
if [[ -x "$NVIM_RELEASE_DIR/bin/nvim" ]]; then
    installed_version="$("$NVIM_RELEASE_DIR/bin/nvim" --version | head -n1 | awk '{print $2}' | sed 's/^v//')"
elif [[ -x "$NVIM_INSTALL_DIR/bin/nvim" ]]; then
    installed_version="$("$NVIM_INSTALL_DIR/bin/nvim" --version | head -n1 | awk '{print $2}' | sed 's/^v//')"
    installed_from_install_dir=1
fi

if [[ "$installed_version" == "${NVIM_VERSION#v}" ]]; then
    if [[ "$installed_from_install_dir" -eq 1 && ! -e "$NVIM_RELEASE_DIR" ]]; then
        echo "==> Promoting existing Neovim ${NVIM_VERSION} install into versioned directory $NVIM_RELEASE_DIR"
        mv "$NVIM_INSTALL_DIR" "$NVIM_RELEASE_DIR"
    else
        echo "==> Neovim ${NVIM_VERSION} already installed in $NVIM_RELEASE_DIR"
    fi
else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    echo "==> Downloading $NVIM_URL"
    curl -fL "$NVIM_URL" -o "$tmpdir/$NVIM_ARCHIVE"
    tar -xzf "$tmpdir/$NVIM_ARCHIVE" -C "$tmpdir"

    mv "$tmpdir/nvim-linux-x86_64" "$tmpdir/nvim-release"
    [[ -x "$tmpdir/nvim-release/bin/nvim" ]] || {
        echo "ERROR: Downloaded Neovim archive did not contain a runnable bin/nvim"
        exit 1
    }
    rm -rf "$NVIM_RELEASE_DIR.tmp"
    mv "$tmpdir/nvim-release" "$NVIM_RELEASE_DIR.tmp"
    mv "$NVIM_RELEASE_DIR.tmp" "$NVIM_RELEASE_DIR"
fi

if [[ -e "$NVIM_INSTALL_DIR" && ! -L "$NVIM_INSTALL_DIR" ]]; then
    legacy_target="$NVIM_OPT_DIR/nvim-linux-x86_64-legacy-$(date +%Y%m%d-%H%M%S)"
    echo "==> Existing $NVIM_INSTALL_DIR is a directory; moving it to $legacy_target"
    mv "$NVIM_INSTALL_DIR" "$legacy_target"
fi

ln -sfn "$NVIM_RELEASE_DIR" "$NVIM_INSTALL_DIR"
ln -sfn "$NVIM_INSTALL_DIR/bin/nvim" "$NVIM_BIN"

if [[ -L "$NVIM_CONFIG" ]]; then
    current_target="$(readlink "$NVIM_CONFIG")"
    if [[ "$current_target" != "$CTT_CONFIG_DIR" ]]; then
        ln -sfn "$CTT_CONFIG_DIR" "$NVIM_CONFIG"
    fi
elif [[ -e "$NVIM_CONFIG" ]]; then
    backup="$HOME/.config/nvim.backup-before-christitustech-$(date +%Y%m%d-%H%M%S)"
    echo "==> Existing ~/.config/nvim is not a symlink; moving it to $backup"
    mv "$NVIM_CONFIG" "$backup"
    ln -s "$CTT_CONFIG_DIR" "$NVIM_CONFIG"
else
    ln -s "$CTT_CONFIG_DIR" "$NVIM_CONFIG"
fi

echo "==> Neovim binary: $("$NVIM_BIN" --version | head -n1)"
echo "==> Neovim config: $NVIM_CONFIG -> $(readlink "$NVIM_CONFIG")"
echo "==> Syncing Neovim plugins to Chris Titus Tech's lockfile..."
"$NVIM_BIN" --headless '+lua vim.pack.update(nil, { target = "lockfile", force = true })' '+qa'
echo "==> Neovim plugins synced to $CTT_CONFIG_DIR/nvim-pack-lock.json"

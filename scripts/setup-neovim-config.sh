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
if [[ -x "$NVIM_INSTALL_DIR/bin/nvim" ]]; then
    installed_version="$("$NVIM_INSTALL_DIR/bin/nvim" --version | head -n1 | awk '{print $2}')"
fi

if [[ "$installed_version" == "${NVIM_VERSION#v}" ]]; then
    echo "==> Neovim ${NVIM_VERSION} already installed in $NVIM_INSTALL_DIR"
else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    echo "==> Downloading $NVIM_URL"
    curl -fL "$NVIM_URL" -o "$tmpdir/$NVIM_ARCHIVE"
    tar -xzf "$tmpdir/$NVIM_ARCHIVE" -C "$tmpdir"

    rm -rf "$NVIM_INSTALL_DIR.tmp"
    mv "$tmpdir/nvim-linux-x86_64" "$NVIM_INSTALL_DIR.tmp"
    rm -rf "$NVIM_INSTALL_DIR"
    mv "$NVIM_INSTALL_DIR.tmp" "$NVIM_INSTALL_DIR"
fi

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
echo "==> First nvim launch will download plugins declared by Chris Titus Tech's config."

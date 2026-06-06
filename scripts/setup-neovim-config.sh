#!/bin/bash
# setup-neovim-config.sh — Chris Titus Tech Neovim config + plugin sync.
#
# Neovim itself now comes from the OS package manager (rpm-ostree on the host,
# dnf in the Fedora toolbox, apt in the Ubuntu container), so the binary is kept
# up to date by the normal system/container update flow — no user-local pinned
# tarball any more. This script only manages the *config* (Chris Titus Tech's
# titus-kickstart) and removes any leftover user-local binary from the old setup
# (a stray ~/.local/bin/nvim would shadow the packaged nvim, since ~/.local/bin
# is first on PATH).
set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
if [[ -f "$DOTFILES/scripts/lib-install.sh" ]]; then
    source "$DOTFILES/scripts/lib-install.sh"
    setup_logging "scripts/setup-neovim-config.sh"
fi

CTT_REPO_DIR="$DOTFILES/nvim/christitustech"
CTT_CONFIG_DIR="$CTT_REPO_DIR/titus-kickstart"
NVIM_CONFIG="$HOME/.config/nvim"

echo "==> Setting up Neovim (Chris Titus Tech config; binary from the package manager)..."

if [[ ! -d "$CTT_REPO_DIR/.git" ]] && [[ ! -f "$CTT_REPO_DIR/.git" ]]; then
    echo "==> Initialising ChrisTitusTech/neovim submodule..."
    git -C "$DOTFILES" submodule update --init --recursive nvim/christitustech
fi

if [[ ! -f "$CTT_CONFIG_DIR/init.lua" ]]; then
    echo "ERROR: Chris Titus Tech Neovim config missing: $CTT_CONFIG_DIR/init.lua"
    exit 1
fi

mkdir -p "$HOME/.config" "$HOME/.vim/undodir" "$HOME/.scripts"

# Remove a previous user-local Neovim install. ~/.local/bin is first on PATH, so
# a leftover ~/.local/bin/nvim symlink would shadow the packaged /usr/bin/nvim.
legacy_removed=0
if [[ -L "$HOME/.local/bin/nvim" || -e "$HOME/.local/bin/nvim" ]]; then
    rm -f "$HOME/.local/bin/nvim"; legacy_removed=1
fi
for d in "$HOME"/.local/opt/nvim-linux-x86_64*; do
    [[ -e "$d" || -L "$d" ]] || continue          # unmatched glob → skip
    rm -rf "$d"; legacy_removed=1
done
# Neovim is no longer a user-local self-registered app (it comes from packages),
# so drop any stale update manifest left by the old setup.
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-updates/nvim"
[[ "$legacy_removed" -eq 1 ]] && \
    echo "==> Removed legacy user-local Neovim (now provided by the package manager)."

# Config symlink → Chris Titus Tech's titus-kickstart.
if [[ -L "$NVIM_CONFIG" ]]; then
    [[ "$(readlink "$NVIM_CONFIG")" != "$CTT_CONFIG_DIR" ]] && ln -sfn "$CTT_CONFIG_DIR" "$NVIM_CONFIG"
elif [[ -e "$NVIM_CONFIG" ]]; then
    backup="$HOME/.config/nvim.backup-before-christitustech-$(date +%Y%m%d-%H%M%S)"
    echo "==> Existing ~/.config/nvim is not a symlink; moving it to $backup"
    mv "$NVIM_CONFIG" "$backup"; ln -s "$CTT_CONFIG_DIR" "$NVIM_CONFIG"
else
    ln -s "$CTT_CONFIG_DIR" "$NVIM_CONFIG"
fi
echo "==> Neovim config: $NVIM_CONFIG -> $(readlink "$NVIM_CONFIG")"

# Plugin sync needs a working nvim. The packaged binary may not be on PATH yet
# during a first host setup (rpm-ostree layering only applies after a reboot), so
# this is best-effort: skip with a clear note rather than failing the whole setup.
# NOTE: Chris Titus Tech's config uses vim.pack, a Neovim 0.12+ feature, so the
# sync (and parts of the config) require nvim >= 0.12.
nvim_bin="$(command -v nvim || true)"
if [[ -n "$nvim_bin" ]]; then
    echo "==> Neovim binary: $("$nvim_bin" --version | head -n1)"
    echo "==> Syncing Neovim plugins to Chris Titus Tech's lockfile..."
    if "$nvim_bin" --headless '+lua vim.pack.update(nil, { target = "lockfile", force = true })' '+qa'; then
        echo "==> Neovim plugins synced to $CTT_CONFIG_DIR/nvim-pack-lock.json"
    else
        echo "==> WARN: plugin sync failed (continuing). Needs Neovim >= 0.12; re-run after upgrading."
    fi
else
    echo "==> Neovim not on PATH yet (likely a pre-reboot host setup)."
    echo "    Install it via the package manager, then re-run:"
    echo "      bash $DOTFILES/scripts/setup-neovim-config.sh"
fi

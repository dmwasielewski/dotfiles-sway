#!/usr/bin/env bash
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-proxmox-client.sh"
policy="${DOTFILES_PROXMOX_POLICY:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/proxmox-client.json}"
if [[ ! -f "$policy" ]]; then
    step_skip PROXMOX_CLIENT
    echo 'No private Proxmox policy; existing trust and hosts preserved'
    exit 0
fi
python3 "$DOTFILES/scripts/proxmox-client.py" validate "$policy"
if python3 "$DOTFILES/scripts/proxmox-client.py" check "$policy" >/dev/null 2>&1; then
    step_done PROXMOX_CLIENT
    echo 'Pinned Proxmox client configuration already current'
else
    # Normal administrator authentication; no passwordless Python grant.
    run_step PROXMOX_CLIENT 'Installing pinned Proxmox client trust and hostname' \
        sudo -n /usr/bin/python3 "$DOTFILES/scripts/proxmox-client.py" apply "$policy"
fi

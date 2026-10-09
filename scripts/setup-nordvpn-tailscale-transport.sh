#!/usr/bin/env bash
# Install only after both products exist; no VPN settings/account changes.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-nordvpn-tailscale-transport.sh"
if ! command -v nordvpn >/dev/null || ! command -v tailscale >/dev/null; then
    step_save NORDVPN_TAILSCALE_TRANSPORT pending
    echo 'NordVPN/Tailscale CLI pending; rerun after installation/reboot'
    exit 0
fi
if ! cmp -s "$DOTFILES/scripts/nordvpn-tailscale-transport.py" /etc/dotfiles/nordvpn-tailscale-transport.py ||
   ! cmp -s "$DOTFILES/systemd/nordvpn-tailscale-transport.service" /etc/dotfiles/nordvpn-tailscale-transport.service; then
    # This copy needs administrator authentication; never allow passwordless
    # execution of a script from the user-controlled repository.
    sudo -n install -Dm0644 -t /etc/dotfiles \
        "$DOTFILES/scripts/nordvpn-tailscale-transport.py" \
        "$DOTFILES/systemd/nordvpn-tailscale-transport.service"
fi
if cmp -s "$DOTFILES/scripts/nordvpn-tailscale-transport.py" /etc/dotfiles/nordvpn-tailscale-transport.py &&
   cmp -s "$DOTFILES/systemd/nordvpn-tailscale-transport.service" /etc/systemd/system/nordvpn-tailscale-transport.service &&
   systemctl is-enabled --quiet nordvpn-tailscale-transport.service &&
   systemctl is-active --quiet nordvpn-tailscale-transport.service; then
    step_done NORDVPN_TAILSCALE_TRANSPORT
    echo 'Tailscale transport compatibility service already current and active'
    exit 0
fi
run_step NORDVPN_TAILSCALE_TRANSPORT 'Installing Tailscale transport compatibility service' \
    sudo -n /usr/bin/python3 /etc/dotfiles/nordvpn-tailscale-transport.py install

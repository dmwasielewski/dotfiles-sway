#!/usr/bin/env bash
# Install only after both products exist; no DNS upstream/account changes.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-adguard-tailscale-dns.sh"
if ! command -v adguard-cli >/dev/null || ! command -v tailscale >/dev/null; then
    step_save ADGUARD_TAILSCALE_DNS pending
    echo 'AdGuard/Tailscale CLI pending; rerun after installation/reboot'
    exit 0
fi
if ! cmp -s "$DOTFILES/scripts/adguard-tailscale-dns.py" /etc/dotfiles/adguard-tailscale-dns.py ||
   ! cmp -s "$DOTFILES/systemd/adguard-tailscale-dns.service" /etc/dotfiles/adguard-tailscale-dns.service; then
    # This copy needs administrator authentication; never allow passwordless
    # execution of a script from the user-controlled repository.
    sudo -n install -Dm0644 -t /etc/dotfiles \
        "$DOTFILES/scripts/adguard-tailscale-dns.py" \
        "$DOTFILES/systemd/adguard-tailscale-dns.service"
fi
if cmp -s "$DOTFILES/scripts/adguard-tailscale-dns.py" /etc/dotfiles/adguard-tailscale-dns.py &&
   cmp -s "$DOTFILES/systemd/adguard-tailscale-dns.service" /etc/systemd/system/adguard-tailscale-dns.service &&
   systemctl is-enabled --quiet adguard-tailscale-dns.service &&
   systemctl is-active --quiet adguard-tailscale-dns.service; then
    step_done ADGUARD_TAILSCALE_DNS
    echo 'Local DNS compatibility service already current and active'
    exit 0
fi
run_step ADGUARD_TAILSCALE_DNS 'Installing local Tailscale DNS compatibility service' \
    sudo -n /usr/bin/python3 /etc/dotfiles/adguard-tailscale-dns.py install

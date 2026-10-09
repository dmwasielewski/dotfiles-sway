#!/usr/bin/env bash
# Host-only: packages.sh configures the repo; phase P2 finishes after reboot.
set -euo pipefail
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-tailscale.sh"

ensure_repo() {
    local target=/etc/yum.repos.d/tailscale.repo
    local content
    # Keep $basearch literal for libdnf expansion.
    # shellcheck disable=SC2016
    content='[tailscale-stable]
name=Tailscale stable
baseurl=https://pkgs.tailscale.com/stable/fedora/$basearch
enabled=1
type=rpm
repo_gpgcheck=1
gpgcheck=1
gpgkey=https://pkgs.tailscale.com/stable/fedora/repo.gpg
skip_if_unavailable=True'
    if [[ -f "$target" ]] && cmp -s "$target" <(printf '%s\n' "$content"); then
        return 0
    fi
    printf '%s\n' "$content" | sudo -n tee "$target" >/dev/null || return 1
}

configure_session() {
    local unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$unit_dir" || return 1
    ln -sfn "$DOTFILES/systemd/tailscale-systray.service" "$unit_dir/tailscale-systray.service" || return 1
    systemctl --user daemon-reload || return 1
    systemctl --user enable tailscale-systray.service || return 1
    if systemctl --user is-active --quiet graphical-session.target; then
        systemctl --user start tailscale-systray.service || return 1
    fi
}

case "${1:-}" in
    --repo-only)
        run_step TAILSCALE_REPO "Configuring official Tailscale repository" ensure_repo
        ;;
    '')
        if ! command -v tailscale >/dev/null; then
            step_save TAILSCALE_READY pending
            echo "Run packages.sh, reboot, then rerun this script."
            exit 1
        fi
        if ! systemctl is-enabled --quiet tailscaled || ! systemctl is-active --quiet tailscaled; then
            run_step TAILSCALE_SERVICE "Enabling Tailscale daemon" sudo -n systemctl enable --now tailscaled
        else
            step_done TAILSCALE_SERVICE
        fi
        operator="$(tailscale debug prefs | python3 -c 'import json,sys; print(json.load(sys.stdin).get("OperatorUser", ""))')"
        if [[ "$operator" != "$USER" ]]; then
            run_step TAILSCALE_OPERATOR "Allowing user to manage Tailscale" sudo -n tailscale set --operator="$USER"
        else
            step_done TAILSCALE_OPERATOR
        fi
        # Optional private opt-in: approval of advertised subnets is managed in
        # the Tailscale admin console. Missing file preserves current preference.
        route_policy="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/tailscale-accept-routes"
        if [[ -f "$route_policy" ]]; then
            accept_routes="$(cat "$route_policy")"
            case "$accept_routes" in
                true|false) ;;
                *) echo "Private Tailscale route policy must contain true or false" >&2; exit 2 ;;
            esac
            run_step TAILSCALE_ROUTES "Applying private subnet-route preference" \
                tailscale set --accept-routes="$accept_routes"
        fi
        run_step TAILSCALE_SYSTRAY "Installing Tailscale session tray service" configure_session
        state="$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState", "Unknown"))')"
        if [[ "$state" == Running ]]; then
            step_done TAILSCALE_LOGIN
        else
            step_save TAILSCALE_LOGIN pending
            echo "Tailscale account login/connection pending: use the tray menu or tailscale up."
        fi
        step_done TAILSCALE_READY
        ;;
    *) echo "Usage: setup-tailscale.sh [--repo-only]" >&2; exit 2 ;;
esac
print_state_summary

#!/bin/bash
# setup-nordvpn.sh — install NordVPN CLI on Fedora Atomic

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-nordvpn.sh"

REPO_FILE="/etc/yum.repos.d/nordvpn.repo"
KEY_FILE="/etc/pki/rpm-gpg/RPM-GPG-KEY-NordVPN"
REPO_URL="https://repo.nordvpn.com/yum/nordvpn/centos"
KEY_URL="https://repo.nordvpn.com/yum/nordvpn/centos/noarch/Packages/n/nordvpn-release-1.0.0-1.noarch.rpm"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   NordVPN — CLI setup                    ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

deployment_has_nordvpn() {
    python3 - <<'PY'
import json
import subprocess
import sys

try:
    data = json.loads(subprocess.check_output(["rpm-ostree", "status", "--json"], text=True))
except Exception:
    sys.exit(1)

for deployment in data.get("deployments", []):
    requested = deployment.get("requested-packages", []) or []
    packages = deployment.get("packages", []) or []
    if "nordvpn" in requested or "nordvpn" in packages:
        sys.exit(0)

sys.exit(1)
PY
}

staged_nordvpn_pending_reboot() {
    python3 - <<'PY'
import json
import subprocess
import sys

try:
    data = json.loads(subprocess.check_output(["rpm-ostree", "status", "--json"], text=True))
except Exception:
    sys.exit(1)

for deployment in data.get("deployments", []):
    if deployment.get("staged") and not deployment.get("booted"):
        requested = deployment.get("requested-packages", []) or []
        packages = deployment.get("packages", []) or []
        if "nordvpn" in requested or "nordvpn" in packages:
            sys.exit(0)

sys.exit(1)
PY
}

ensure_repo() {
    # Idempotent: if the repo file and GPG key are already in place, there is
    # nothing to download — succeed without touching the network or sudo. This
    # is the common case on re-runs and must NOT fail when repo.nordvpn.com is
    # unreachable.
    if [[ -f "$REPO_FILE" && -f "$KEY_FILE" ]]; then
        echo "NordVPN repo + GPG key already configured — skipping download"
        return 0
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    # A RETURN trap set in a function is NOT scoped to it: it survives that
    # function's return and fires again when the ENCLOSING function returns —
    # here run_step, which called this one. By then $tmpdir is out of scope, so
    # `set -u` aborts the install with "tmpdir: unbound variable" blamed on
    # lib-install.sh, a file that never mentions tmpdir. Clear the trap as it
    # fires, and default the expansion so a stray firing cannot crash anything.
    # Only reachable on a fresh install: an already-configured machine returns
    # above, before the trap is ever set, which is why this never showed up here.
    trap 'rm -rf "${tmpdir:-}"; trap - RETURN' RETURN
    if ! command -v rpm2cpio >/dev/null 2>&1; then
        echo "rpm2cpio is required to unpack the NordVPN release RPM" >&2
        return 1
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required; run 'sudo -v' in a terminal and rerun this script" >&2
        return 1
    fi

    # set -e does not apply inside a function tested by `if` (run_step), so each
    # critical step must check its own exit status and fail loudly — otherwise a
    # download failure is masked by the final `tee` succeeding (false green).
    if ! curl -fL -o "$tmpdir/nordvpn-release.rpm" "$KEY_URL"; then
        echo "Could not download the NordVPN release RPM from $KEY_URL — repo unreachable" >&2
        return 1
    fi
    if ! (cd "$tmpdir" && rpm2cpio nordvpn-release.rpm | cpio -idm >/dev/null 2>&1); then
        echo "Failed to unpack the NordVPN release RPM" >&2
        return 1
    fi
    if [[ ! -f "$tmpdir/etc/pki/rpm-gpg/RPM-GPG-KEY-NordVPN" ]]; then
        echo "GPG key not found in the unpacked RPM" >&2
        return 1
    fi

    sudo -n install -Dm0644 "$tmpdir/etc/pki/rpm-gpg/RPM-GPG-KEY-NordVPN" "$KEY_FILE" || return 1
    sudo -n install -Dm0644 /dev/null "$REPO_FILE" || return 1
    sudo -n tee "$REPO_FILE" >/dev/null <<EOF
####################################################################
# NordVPN releases, stable                                         #
####################################################################
[nordvpn]
name = NordVPN YUM repository - \$basearch
baseurl = ${REPO_URL}/\$basearch
enabled = 1
gpgcheck = 1
gpgkey = file://${KEY_FILE}
skip_if_unavailable = True

[nordvpn-noarch]
name = NordVPN YUM repository - noarch
baseurl = ${REPO_URL}/noarch
enabled = 1
gpgcheck = 1
gpgkey = file://${KEY_FILE}
skip_if_unavailable = True
EOF
}

# rpm-ostree aborts its ENTIRE metadata refresh if a single enabled repo is
# unreachable. repo.nordvpn.com is regularly unreachable here — most reliably
# while the NordVPN tunnel is connected, when it stops resolving — which would
# otherwise make every `rpm-ostree upgrade --check` fail and freeze the Waybar
# update indicator on a stale "updates pending" (amber). skip_if_unavailable
# tells libdnf/rpm-ostree to skip this third-party repo when it is down instead
# of failing the whole operation. Idempotent: only add it where it is missing,
# so it also heals repo files written before this directive existed.
ensure_repo_resilient() {
    [[ -f "$REPO_FILE" ]] || return 0
    grep -q '^[[:space:]]*skip_if_unavailable' "$REPO_FILE" && return 0
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required to add skip_if_unavailable to $REPO_FILE; run 'sudo -v' and rerun" >&2
        return 1
    fi
    # Append the directive after each NordVPN section header ([nordvpn], [nordvpn-noarch]).
    sudo -n sed -i '/^\[nordvpn/a skip_if_unavailable = True' "$REPO_FILE"
}

run_step "NORDVPN_REPO" "Configuring NordVPN repository" ensure_repo
run_step "NORDVPN_REPO_RESILIENT" "Making NordVPN repo non-fatal when offline" ensure_repo_resilient

if command -v nordvpn >/dev/null 2>&1; then
    echo "==> NordVPN CLI already installed — skipping install."
    step_done "NORDVPN_CLI"
elif staged_nordvpn_pending_reboot; then
    echo "==> NordVPN CLI is already queued in a staged rpm-ostree deployment — reboot required."
    step_done "NORDVPN_CLI"
elif deployment_has_nordvpn; then
    echo "==> NordVPN CLI is already requested in rpm-ostree — skipping install."
    step_done "NORDVPN_CLI"
else
    run_step "NORDVPN_CLI" "Installing NordVPN CLI" sudo -n rpm-ostree install nordvpn
fi

if command -v nordvpn >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    if systemctl list-unit-files nordvpnd.service 2>/dev/null | grep -q '^nordvpnd\.service'; then
        if systemctl is-enabled --quiet nordvpnd 2>/dev/null && systemctl is-active --quiet nordvpnd 2>/dev/null; then
            echo "==> NordVPN background service already enabled and running — skipping."
            step_done "NORDVPN_SERVICE"
        else
            run_step "NORDVPN_SERVICE" "Enabling NordVPN background service" sudo -n systemctl enable --now nordvpnd
        fi
    else
        echo -e "${YELLOW}⚠ nordvpnd.service not available yet — reboot may still be required before the service can be enabled${NC}"
    fi
fi

if getent group nordvpn >/dev/null 2>&1; then
    if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx nordvpn; then
        echo "==> User already in nordvpn group — skipping."
        step_done "NORDVPN_GROUP"
    else
        run_step_warn "NORDVPN_GROUP" "Adding user to nordvpn group" sudo usermod -aG nordvpn "$USER"
        echo "==> Re-log in or reboot so the nordvpn group membership takes effect."
    fi
else
    echo -e "${YELLOW}⚠ nordvpn group not present yet — finish login/reboot after the CLI install${NC}"
fi

# Aggregate readiness reflects the real end state instead of being hardcoded to
# done. NordVPN is layered via rpm-ostree, so on the first (pre-reboot) run the
# command, daemon and group typically do not exist yet — that is "pending"
# (finish the reboot/login and re-run), NOT "ready".
nordvpn_ready=1
command -v nordvpn >/dev/null 2>&1 || nordvpn_ready=0
systemctl is-active --quiet nordvpnd 2>/dev/null || nordvpn_ready=0
id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx nordvpn || nordvpn_ready=0
if [[ "$nordvpn_ready" == "1" ]]; then
    step_done "NORDVPN_READY"
else
    step_save "NORDVPN_READY" "pending"
    echo -e "${YELLOW}⚠ NordVPN not fully ready yet (CLI/daemon/group pending) — finish the reboot/login, then re-run this script.${NC}"
fi

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} NordVPN CLI setup complete${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Check status with: nordvpn status"
echo "Connect with:       nordvpn connect"
echo "Disconnect with:    nordvpn disconnect"
echo ""
print_state_summary

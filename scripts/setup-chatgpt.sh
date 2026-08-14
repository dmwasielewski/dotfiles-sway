#!/bin/bash
# setup-chatgpt.sh — install the official ChatGPT desktop app on Fedora Atomic
#
# The app bundles ChatGPT, ChatGPT Work and Codex in one window (Codex is a
# workspace inside it, not a separate application). Upstream ships .rpm/.deb only
# and documents `dnf install ./chatgpt.x86_64.rpm`, which is wrong for an
# immutable host, so this script layers it with rpm-ostree instead.
#
# It deliberately installs BY NAME from OpenAI's repository rather than layering
# the downloaded file. A locally layered .rpm is pinned to that exact file and is
# never seen by `rpm-ostree upgrade`, which would leave the app permanently
# invisible to the Waybar update indicator. Installing by name puts it in the OS
# update path like every other layered package.
#
# The repository is signed with a key that upstream publishes ONLY inside the
# package's %post scriptlet — there is no public key URL (checked: /gpg,
# /gpg.key, /RPM-GPG-KEY-chatgpt all 404). So the key is extracted from the
# package at runtime rather than copied into this repo, which means a key
# rotation is picked up automatically instead of silently breaking gpgcheck.

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
# shellcheck source=scripts/lib-install.sh
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-chatgpt.sh"

PKG="chatgpt"
REPO_FILE="/etc/yum.repos.d/chatgpt.repo"
KEY_FILE="/etc/pki/rpm-gpg/RPM-GPG-KEY-chatgpt"
REPO_SECTION="openai-chatgpt"
# $basearch is a dnf variable, expanded by the package manager — not by bash.
# shellcheck disable=SC2016
REPO_BASEURL='https://persistent.oaistatic.com/codex-app-prod/linux/rpm/$basearch'
RPM_URL="https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm"
RPM_CACHE="${CHATGPT_RPM:-$HOME/Downloads/chatgpt.x86_64.rpm}"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   ChatGPT desktop (incl. Codex) — setup  ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# --- rpm-ostree deployment state -------------------------------------------
# Both helpers take the package name so nothing about this app is baked into
# the logic; they mirror the checks in setup-nordvpn.sh.

deployment_has_pkg() {
    PKG_NAME="$1" python3 - <<'PY'
import json, os, subprocess, sys

name = os.environ["PKG_NAME"]
try:
    data = json.loads(subprocess.check_output(["rpm-ostree", "status", "--json"], text=True))
except Exception:
    sys.exit(1)

for deployment in data.get("deployments", []):
    requested = deployment.get("requested-packages", []) or []
    packages = deployment.get("packages", []) or []
    if name in requested or name in packages:
        sys.exit(0)
sys.exit(1)
PY
}

staged_pkg_pending_reboot() {
    PKG_NAME="$1" python3 - <<'PY'
import json, os, subprocess, sys

name = os.environ["PKG_NAME"]
try:
    data = json.loads(subprocess.check_output(["rpm-ostree", "status", "--json"], text=True))
except Exception:
    sys.exit(1)

for deployment in data.get("deployments", []):
    if deployment.get("staged") and not deployment.get("booted"):
        requested = deployment.get("requested-packages", []) or []
        packages = deployment.get("packages", []) or []
        if name in requested or name in packages:
            sys.exit(0)
sys.exit(1)
PY
}

# --- repository ------------------------------------------------------------

fetch_rpm() {
    if [[ -s "$RPM_CACHE" ]]; then
        echo "==> Reusing already downloaded package: $RPM_CACHE"
        return 0
    fi
    mkdir -p "$(dirname "$RPM_CACHE")"
    curl -fL --retry 3 -o "$RPM_CACHE" "$RPM_URL"
}

REPOMD_CACHE="/var/cache/rpm-ostree/repomd"

key_is_armoured() {
    [[ -s "$1" ]] && head -1 "$1" 2>/dev/null | grep -q 'BEGIN PGP PUBLIC KEY BLOCK'
}

install_key() {
    if key_is_armoured "$KEY_FILE"; then
        echo "==> Signing key already present (ASCII-armoured) — skipping."
        return 0
    fi
    if [[ -s "$KEY_FILE" ]]; then
        echo "==> Existing key is not ASCII-armoured — replacing it."
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required to install $KEY_FILE; run 'sudo -v' and rerun" >&2
        return 1
    fi
    # Pull the base64 key out of the package's own %post scriptlet. Upstream
    # writes it there and nowhere else.
    local key_b64
    key_b64="$(rpm -qp --scripts "$RPM_CACHE" 2>/dev/null |
        sed -n "s/^SIGNING_KEY_BASE64='\(.*\)'$/\1/p")"
    if [[ -z "$key_b64" ]]; then
        echo "Could not find SIGNING_KEY_BASE64 in $RPM_CACHE — upstream changed the scriptlet." >&2
        return 1
    fi

    # Upstream stores the key as a raw binary keyring and its own %post writes it
    # out unchanged. dnf tolerates that; rpm-ostree does NOT — it fails the whole
    # install with "PKI file ... contains no valid public key" (observed
    # 2026-08-14, after resolving and downloading all 447 MB). Re-armour it.
    local workdir
    workdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$workdir'" RETURN
    chmod 700 "$workdir"
    printf '%s' "$key_b64" | base64 -d > "$workdir/key.bin"
    if ! GNUPGHOME="$workdir" gpg --batch --quiet --import "$workdir/key.bin" 2>/dev/null; then
        echo "Extracted key from $RPM_CACHE is not a valid OpenPGP key." >&2
        return 1
    fi
    GNUPGHOME="$workdir" gpg --batch --armor --export > "$workdir/key.asc" 2>/dev/null
    if ! key_is_armoured "$workdir/key.asc"; then
        echo "Failed to ASCII-armour the signing key." >&2
        return 1
    fi

    sudo -n mkdir -p "$(dirname "$KEY_FILE")"
    sudo -n tee "$KEY_FILE" < "$workdir/key.asc" >/dev/null
    sudo -n chmod 0644 "$KEY_FILE"
}

# rpm-ostree does not read gpgkey from /etc at install time: it copies the key
# into $REPOMD_CACHE/<repo>-<release>-<arch>/ on the first metadata refresh and
# then trusts that copy. Fixing only the source file leaves the stale one in
# place, so the install keeps failing with the same error. Compare the two
# rather than tracking whether we just wrote the key — that stays correct even
# if a previous run died between writing the key and clearing the cache.
drop_stale_metadata() {
    local cached stale=0
    while IFS= read -r cached; do
        [[ -n "$cached" ]] || continue
        cmp -s "$cached" "$KEY_FILE" || stale=1
    done < <(find "$REPOMD_CACHE" -maxdepth 2 -name "$(basename "$KEY_FILE")" \
                  -path "*/$REPO_SECTION-*" 2>/dev/null)

    if [[ "$stale" -eq 0 ]]; then
        echo "==> Cached metadata already matches the installed key — nothing to drop."
        return 0
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required to clear the rpm-ostree metadata cache; run 'sudo -v' and rerun" >&2
        return 1
    fi
    echo "==> Cached key differs from $KEY_FILE — dropping rpm-ostree metadata cache."
    sudo -n rpm-ostree cleanup -m
}

ensure_repo() {
    if [[ -f "$REPO_FILE" ]]; then
        echo "==> Repository already configured — skipping."
        return 0
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required to write $REPO_FILE; run 'sudo -v' and rerun" >&2
        return 1
    fi
    # skip_if_unavailable is written in from the start, not patched in later:
    # rpm-ostree aborts its WHOLE metadata refresh when any one enabled repo is
    # unreachable, which is exactly how the NordVPN repo used to freeze the
    # Waybar update indicator on a stale value.
    sudo -n tee "$REPO_FILE" >/dev/null <<EOF
[$REPO_SECTION]
name=ChatGPT
baseurl=$REPO_BASEURL
enabled=1
type=rpm-md
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$KEY_FILE
skip_if_unavailable = True
EOF
    sudo -n chmod 0644 "$REPO_FILE"
}

ensure_repo_resilient() {
    [[ -f "$REPO_FILE" ]] || return 0
    grep -q '^[[:space:]]*skip_if_unavailable' "$REPO_FILE" && return 0
    if ! sudo -n true >/dev/null 2>&1; then
        echo "sudo credentials are required to add skip_if_unavailable to $REPO_FILE; run 'sudo -v' and rerun" >&2
        return 1
    fi
    # Heals a repo file written by upstream's own %post, which omits the flag.
    sudo -n sed -i "/^\[$REPO_SECTION/a skip_if_unavailable = True" "$REPO_FILE"
}

run_step "CHATGPT_RPM"       "Downloading ChatGPT package (signing key source)" fetch_rpm
run_step "CHATGPT_KEY"       "Installing OpenAI signing key"                    install_key
run_step "CHATGPT_REPO"      "Configuring ChatGPT repository"                   ensure_repo
run_step "CHATGPT_REPO_RESILIENT" "Making ChatGPT repo non-fatal when offline"  ensure_repo_resilient
run_step "CHATGPT_METADATA"  "Dropping cached metadata holding the old key"      drop_stale_metadata

if command -v chatgpt >/dev/null 2>&1; then
    echo "==> ChatGPT already installed — skipping install."
    step_done "CHATGPT_APP"
elif staged_pkg_pending_reboot "$PKG"; then
    echo "==> ChatGPT is already queued in a staged rpm-ostree deployment — reboot required."
    step_done "CHATGPT_APP"
elif deployment_has_pkg "$PKG"; then
    echo "==> ChatGPT is already requested in rpm-ostree — skipping install."
    step_done "CHATGPT_APP"
else
    run_step "CHATGPT_APP" "Installing ChatGPT desktop app" sudo -n rpm-ostree install "$PKG"
fi

echo ""
echo -e "${GREEN}${BOLD}ChatGPT desktop setup finished.${NC}"
echo ""
echo -e " Reboot to activate:  ${CYAN}systemctl reboot${NC}"
echo -e " Then launch with:    ${CYAN}chatgpt${NC}  (or from the app launcher)"
echo ""
echo -e " Codex is a workspace ${BOLD}inside${NC} this app — switch with the menu in the"
echo -e " top-left corner. There is no separate Codex application for Linux."
echo -e " The ${CYAN}codex${NC} CLI in toolbox ${CYAN}damianf${NC} stays as it is; both use the"
echo -e " same OpenAI account."
echo ""

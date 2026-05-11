#!/bin/bash
# setup-security-container.sh — Ubuntu 26.04 distrobox with full pentesting toolkit
# Run after first reboot: bash ~/dotfiles-sway/scripts/setup-security-container.sh

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-security-container.sh"

SECURITY_VERSION="26.04"
BASE_IMAGE="docker.io/library/ubuntu:${SECURITY_VERSION}"
FIXED_IMAGE="localhost/ubuntu-security:${SECURITY_VERSION}"

# Helper: run command inside the security container
dbox() { distrobox enter --name security -- bash -lc "set -euo pipefail; $*"; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Distrobox 'security' — setup           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

require_sudo_session

# ── Build image with apt HTTP pipeline disabled ──────────────────────────
if ! podman image exists "$FIXED_IMAGE" 2>/dev/null; then
    echo -e "${CYAN}==> Building Ubuntu ${SECURITY_VERSION} image with apt HTTP pipeline disabled...${NC}"
    printf 'FROM %s\nRUN printf "Acquire::http::Pipeline-Depth \\"0\\";\\nAcquire::Retries \\"5\\";\\n" > /etc/apt/apt.conf.d/99-no-pipeline && apt-get update -qq\n' \
        "$BASE_IMAGE" | podman build -t "$FIXED_IMAGE" - 2>&1 | tail -3
    echo -e "${GREEN}✓ Image built${NC}"
fi

# ── Create container if missing ──────────────────────────────────────────
if podman container exists security 2>/dev/null; then
    CURRENT_VERSION="$(distrobox enter --name security -- bash -lc '. /etc/os-release && printf "%s" "$VERSION_ID"' 2>/dev/null || true)"
    if [[ "$CURRENT_VERSION" != "$SECURITY_VERSION" ]]; then
        echo -e "${RED}✗ Container 'security' exists, but is Ubuntu ${CURRENT_VERSION:-unknown}; expected ${SECURITY_VERSION}.${NC}"
        echo -e "${YELLOW}  Recreate it manually if you want to upgrade:${NC}"
        echo -e "${YELLOW}  distrobox stop security --yes && distrobox rm security --force${NC}"
        echo -e "${YELLOW}  bash ~/dotfiles-sway/scripts/setup-security-container.sh${NC}"
        step_failed "SECURITY_CREATED"
        exit 1
    fi
    echo -e "${YELLOW}==> Container 'security' already exists on Ubuntu ${SECURITY_VERSION} — skipping creation.${NC}"
    step_done "SECURITY_CREATED"
else
    run_step "SECURITY_CREATED" "Creating security container (Ubuntu ${SECURITY_VERSION})" \
        distrobox create --name security --image "$FIXED_IMAGE"
fi

# ── Base packages ────────────────────────────────────────────────────────
run_step "SECURITY_BASE_PKGS" "Installing base packages" \
    dbox "sudo apt-get update -qq &&
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            nmap wireshark netcat-openbsd tcpdump curl wget git \
            htop btop python3 python3-pip python3-venv \
            ruby rubygems build-essential cmake pkg-config \
            libssl-dev libffi-dev cargo"

# ── Security tools ───────────────────────────────────────────────────────
run_step "SECURITY_TOOLS" "Installing security tools (hydra, sqlmap, gobuster, hashcat, ...)" \
    dbox "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing \
            hydra sqlmap nikto john hashcat socat binwalk foremost steghide \
            libimage-exiftool-perl masscan dirb wfuzz gobuster ffuf medusa \
            aircrack-ng tmux vim jq net-tools dnsutils whois"

# ── Python security libraries ────────────────────────────────────────────
run_step "SECURITY_PYTHON_LIBS" "Installing Python security libraries (impacket, pwntools)" \
    dbox "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            python3-pwntools python3-unicorn libunicorn-dev &&
        pip3 install impacket --break-system-packages &&
        if ! grep -q '.local/bin' ~/.bashrc; then echo 'export PATH=\$PATH:\$HOME/.local/bin' >> ~/.bashrc; fi &&
        python3 -c 'import impacket, pwn, unicorn'"

# ── Metasploit Framework ─────────────────────────────────────────────────
run_step "SECURITY_METASPLOIT" "Installing Metasploit Framework" \
    dbox "curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall &&
        chmod +x /tmp/msfinstall &&
        sudo /tmp/msfinstall"

# ── evil-winrm ───────────────────────────────────────────────────────────
run_step "SECURITY_EVIL_WINRM" "Installing evil-winrm" \
    dbox "sudo apt-get install -y --fix-missing ruby-dev libkrb5-dev 2>/dev/null || true &&
        sudo gem install evil-winrm"

# ── enum4linux-ng ────────────────────────────────────────────────────────
run_step_warn "SECURITY_ENUM4LINUX" "Installing enum4linux-ng" \
    dbox "if [ -d /opt/enum4linux-ng/.git ]; then
            sudo git -C /opt/enum4linux-ng pull --ff-only
          elif [ -e /opt/enum4linux-ng ]; then
            echo 'WARNING: /opt/enum4linux-ng exists but is not a git checkout; skipping enum4linux-ng setup.' >&2
            exit 1
          else
            sudo git clone --depth 1 https://github.com/cddmp/enum4linux-ng /opt/enum4linux-ng
          fi &&
        pip3 install -r /opt/enum4linux-ng/requirements.txt --break-system-packages &&
        sudo ln -sf /opt/enum4linux-ng/enum4linux-ng.py /usr/local/bin/enum4linux-ng"

# ── SecLists wordlists ───────────────────────────────────────────────────
run_step_warn "SECURITY_SECLISTS" "Downloading SecLists wordlists (~1 GB — may take a while)" \
    dbox "if [ -d /opt/SecLists/.git ]; then
            sudo git -C /opt/SecLists pull --ff-only
          elif [ -e /opt/SecLists ]; then
            echo 'WARNING: /opt/SecLists exists but is not a git checkout; skipping SecLists setup.' >&2
            exit 1
          else
            sudo git clone --depth 1 https://github.com/danielmiessler/SecLists /opt/SecLists
          fi"

step_done "SECURITY_CONTAINER_READY"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Security container ready!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " Enter container:  ${CYAN}distrobox enter security${NC}"
echo ""
echo -e " Key paths:"
echo -e "   Wordlists:  ${CYAN}/opt/SecLists${NC}"
echo -e "   MSF:        ${CYAN}msfconsole${NC}"
echo -e "   WinRM:      ${CYAN}evil-winrm${NC}"
echo ""
print_state_summary

#!/bin/bash
# setup-security-container.sh — Ubuntu 24.04 LTS distrobox with full pentesting toolkit
# NOTE: Ubuntu 26.04 repos have CDN issues (400 errors) as of April 2026.
#       To upgrade later: remove container, change IMAGE to ubuntu:26.04, re-run.
# Run after first reboot: bash ~/dotfiles-sway/scripts/setup-security-container.sh

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/setup-security-container.sh"

BASE_IMAGE="docker.io/library/ubuntu:24.04"
FIXED_IMAGE="localhost/ubuntu-security:24.04"

# Helper: run command inside the security container
dbox() { distrobox enter --name security -- bash -c "$*"; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Distrobox 'security' — setup           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Build image with working mirror (Canonical CDN has issues) ───────────
if ! podman image exists "$FIXED_IMAGE" 2>/dev/null; then
    echo -e "${CYAN}==> Building Ubuntu image with kernel.org mirror (avoids Canonical CDN issues)...${NC}"
    printf 'FROM %s\nRUN sed -i "s|http://archive.ubuntu.com/ubuntu/|http://mirrors.edge.kernel.org/ubuntu/|g; s|http://security.ubuntu.com/ubuntu/|http://mirrors.edge.kernel.org/ubuntu/|g" /etc/apt/sources.list.d/ubuntu.sources && apt-get update -qq\n' \
        "$BASE_IMAGE" | podman build -t "$FIXED_IMAGE" - 2>&1 | tail -3
    echo -e "${GREEN}✓ Image built${NC}"
fi

# ── Create container if missing ──────────────────────────────────────────
if distrobox list 2>/dev/null | grep -q "security"; then
    echo -e "${YELLOW}==> Container 'security' already exists — skipping creation.${NC}"
    step_done "SECURITY_CREATED"
else
    run_step "SECURITY_CREATED" "Creating security container (Ubuntu 24.04 LTS)" \
        distrobox create --name security --image "$FIXED_IMAGE"
fi

# ── Base packages ────────────────────────────────────────────────────────
run_step "SECURITY_BASE_PKGS" "Installing base packages" \
    dbox "sudo apt-get update -qq &&
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            nmap wireshark netcat-openbsd tcpdump curl wget git \
            htop btop python3 python3-pip python3-venv \
            ruby rubygems build-essential libssl-dev libffi-dev cargo"

# ── Security tools ───────────────────────────────────────────────────────
run_step "SECURITY_TOOLS" "Installing security tools (hydra, sqlmap, gobuster, hashcat, ...)" \
    dbox "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing \
            hydra sqlmap nikto john hashcat socat binwalk foremost steghide \
            libimage-exiftool-perl masscan dirb wfuzz gobuster ffuf medusa \
            aircrack-ng tmux vim jq net-tools dnsutils whois"

# ── Python security libraries ────────────────────────────────────────────
run_step "SECURITY_PYTHON_LIBS" "Installing Python security libraries (impacket, pwntools)" \
    dbox "pip3 install impacket pwntools --break-system-packages &&
        grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\$PATH:\$HOME/.local/bin' >> ~/.bashrc"

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
run_step "SECURITY_ENUM4LINUX" "Installing enum4linux-ng" \
    dbox "sudo git clone --depth 1 https://github.com/cddmp/enum4linux-ng /opt/enum4linux-ng 2>/dev/null || (cd /opt/enum4linux-ng && sudo git pull) &&
        pip3 install -r /opt/enum4linux-ng/requirements.txt --break-system-packages &&
        sudo ln -sf /opt/enum4linux-ng/enum4linux-ng.py /usr/local/bin/enum4linux-ng"

# ── SecLists wordlists ───────────────────────────────────────────────────
run_step "SECURITY_SECLISTS" "Downloading SecLists wordlists (~1 GB — may take a while)" \
    dbox "sudo git clone --depth 1 https://github.com/danielmiessler/SecLists /opt/SecLists 2>/dev/null || echo 'SecLists already exists — skipping.'"

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

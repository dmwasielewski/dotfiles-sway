#!/bin/bash
# setup-security-container.sh — Ubuntu 26.04 LTS distrobox with full pentesting toolkit
# Run after first reboot: bash ~/dotfiles-sway/scripts/setup-security-container.sh

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Distrobox 'security' — setup           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Create container if missing ──────────────────────────────────────────
if distrobox list 2>/dev/null | grep -q "security"; then
    echo -e "${YELLOW}==> Container 'security' already exists — skipping creation.${NC}"
    step_done "SECURITY_CREATED"
else
    run_step "SECURITY_CREATED" "Creating security container (Ubuntu 24.04)" \
        distrobox create --name security --image ubuntu:26.04
fi

# ── Base packages ────────────────────────────────────────────────────────
run_step "SECURITY_BASE_PKGS" "Installing base packages" \
    distrobox run --name security -- bash -c "
        sudo apt-get update -qq &&
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            nmap wireshark netcat-openbsd tcpdump curl wget git \
            htop btop python3 python3-pip python3-venv \
            ruby rubygems build-essential libssl-dev libffi-dev cargo
    "

# ── Security tools ───────────────────────────────────────────────────────
run_step "SECURITY_TOOLS" "Installing security tools (hydra, sqlmap, gobuster, hashcat, ...)" \
    distrobox run --name security -- bash -c "
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing \
            hydra sqlmap nikto john hashcat socat binwalk foremost steghide \
            libimage-exiftool-perl masscan dirb wfuzz gobuster ffuf medusa \
            aircrack-ng tmux vim jq net-tools dnsutils whois
    "

# ── Python security libraries ────────────────────────────────────────────
run_step "SECURITY_PYTHON_LIBS" "Installing Python security libraries (impacket, pwntools)" \
    distrobox run --name security -- bash -c "
        pip3 install impacket pwntools --break-system-packages
        grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\$PATH:\$HOME/.local/bin' >> ~/.bashrc
    "

# ── Metasploit Framework ─────────────────────────────────────────────────
run_step "SECURITY_METASPLOIT" "Installing Metasploit Framework" \
    distrobox run --name security -- bash -c "
        curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall
        chmod +x /tmp/msfinstall
        sudo /tmp/msfinstall
    "

# ── evil-winrm ───────────────────────────────────────────────────────────
run_step "SECURITY_EVIL_WINRM" "Installing evil-winrm" \
    distrobox run --name security -- bash -c "
        sudo apt-get install -y --fix-missing ruby-dev libkrb5-dev 2>/dev/null || true
        sudo gem install evil-winrm
    "

# ── enum4linux-ng ────────────────────────────────────────────────────────
run_step "SECURITY_ENUM4LINUX" "Installing enum4linux-ng" \
    distrobox run --name security -- bash -c "
        sudo git clone --depth 1 https://github.com/cddmp/enum4linux-ng /opt/enum4linux-ng 2>/dev/null || \
            (cd /opt/enum4linux-ng && sudo git pull)
        pip3 install -r /opt/enum4linux-ng/requirements.txt --break-system-packages
        sudo ln -sf /opt/enum4linux-ng/enum4linux-ng.py /usr/local/bin/enum4linux-ng
    "

# ── SecLists wordlists ───────────────────────────────────────────────────
run_step "SECURITY_SECLISTS" "Downloading SecLists wordlists (~1 GB — may take a while)" \
    distrobox run --name security -- bash -c "
        sudo git clone --depth 1 https://github.com/danielmiessler/SecLists /opt/SecLists 2>/dev/null || \
            echo 'SecLists already exists — skipping.'
    "

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

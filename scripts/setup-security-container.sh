#!/bin/bash
set -e

# Skip if container already exists
if distrobox list | grep -q "security"; then
    echo "==> Container 'security' already exists — skipping creation."
else
    echo "==> Creating security container..."
    distrobox create --name security --image ubuntu:24.04
fi

echo "==> Installing base packages..."
distrobox run --name security -- bash -c "
    sudo apt-get update -qq &&
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nmap \
        wireshark \
        netcat-openbsd \
        tcpdump \
        curl \
        wget \
        git \
        htop \
        btop \
        python3 \
        python3-pip \
        python3-venv \
        ruby \
        rubygems \
        build-essential \
        libssl-dev \
        libffi-dev \
        cargo
"

echo "==> Installing security tools (apt)..."
distrobox run --name security -- bash -c "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing \
        hydra \
        sqlmap \
        nikto \
        john \
        hashcat \
        socat \
        binwalk \
        foremost \
        steghide \
        libimage-exiftool-perl \
        masscan \
        dirb \
        wfuzz \
        gobuster \
        ffuf \
        medusa \
        aircrack-ng \
        tmux \
        vim \
        jq \
        net-tools \
        dnsutils \
        whois
"

echo "==> Installing Python security libraries..."
distrobox run --name security -- bash -c "
    pip3 install impacket pwntools --break-system-packages
    grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\$PATH:\$HOME/.local/bin' >> ~/.bashrc
"

echo "==> Installing Metasploit Framework..."
distrobox run --name security -- bash -c "
    curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall
    chmod +x /tmp/msfinstall
    sudo /tmp/msfinstall
"

echo "==> Installing evil-winrm (WinRM shell)..."
distrobox run --name security -- bash -c "
    sudo apt-get install -y --fix-missing ruby-dev libkrb5-dev 2>/dev/null || true
    sudo gem install evil-winrm
"

echo "==> Installing enum4linux-ng..."
distrobox run --name security -- bash -c "
    sudo git clone --depth 1 https://github.com/cddmp/enum4linux-ng /opt/enum4linux-ng 2>/dev/null || \
        (cd /opt/enum4linux-ng && sudo git pull)
    pip3 install -r /opt/enum4linux-ng/requirements.txt --break-system-packages
    sudo ln -sf /opt/enum4linux-ng/enum4linux-ng.py /usr/local/bin/enum4linux-ng
"

echo "==> Installing SecLists wordlists..."
distrobox run --name security -- bash -c "
    sudo git clone --depth 1 https://github.com/danielmiessler/SecLists /opt/SecLists 2>/dev/null || \
        echo '==> SecLists already exists — skipping.'
"

echo ""
echo "=============================================="
echo " Security container ready!"
echo " Enter: distrobox enter security"
echo ""
echo " Key paths:"
echo "   Wordlists: /opt/SecLists"
echo "   MSF:       msfconsole"
echo "   WinRM:     evil-winrm"
echo "=============================================="

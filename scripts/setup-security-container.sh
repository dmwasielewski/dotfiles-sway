#!/bin/bash
set -e

# Skip if container already exists
if distrobox list | grep -q "security"; then
    echo "==> Container 'security' already exists — skipping creation."
else
    echo "==> Creating security container..."
    distrobox create --name security --image ubuntu:24.04
fi

echo "==> Installing security tools..."
distrobox run --name security -- bash -c "
    sudo apt update &&
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        nmap \
        wireshark \
        netcat-openbsd \
        curl \
        wget \
        git \
        htop \
        btop
"

echo "==> Security container ready. Enter with: distrobox enter security"

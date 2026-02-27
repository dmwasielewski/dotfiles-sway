#!/bin/bash
set -e

echo "==> Creating security container..."
distrobox create --name security --image ubuntu:24.04

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

#!/bin/bash
# setup-splunk.sh — installs Splunk Free in the security distrobox container
# Optional lab tool for SIEM learning (SC-200 supplementary)
# Not part of automated bootstrap — run manually when needed.
set -euo pipefail

SPLUNK_DEB="${SPLUNK_DEB:-https://download.splunk.com/products/splunk/releases/9.4.0/linux/splunk-9.4.0-6b4ac2fa5cd0-linux-2.6-amd64.deb}"

echo "==> Installing Splunk Free in security container..."
echo "    This may take a few minutes..."

distrobox enter security -- bash -lc "
    set -euo pipefail
    if [ -f /opt/splunk/bin/splunk ]; then
        echo '==> Splunk already installed — skipping download.'
    else
        echo '==> Downloading Splunk...'
        cd /tmp
        wget -q --show-progress -O splunk.deb '$SPLUNK_DEB'
        echo '==> Installing...'
        sudo dpkg -i splunk.deb 2>/dev/null || sudo apt-get install -f -y
        rm -f splunk.deb
    fi
    echo '==> Starting Splunk...'
    sudo /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt 2>/dev/null || true
    sudo /opt/splunk/bin/splunk enable boot-start 2>/dev/null || true
"

echo ""
echo "==> Splunk is ready."
echo "    Web UI:  http://localhost:8000"
echo "    Login:   admin / changeme (change on first login)"
echo ""
echo "    After reboot, enter the container and start Splunk:"
echo "      distrobox enter security"
echo "      sudo /opt/splunk/bin/splunk start"

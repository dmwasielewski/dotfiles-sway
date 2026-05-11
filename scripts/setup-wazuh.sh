#!/bin/bash
# setup-wazuh.sh — deploys Wazuh all-in-one via podman
# Optional lab tool for SIEM/XDR learning (SC-200 supplementary)
# Not part of automated bootstrap — run manually when needed.
# Clean up: podman stop wazuh-indexer wazuh-manager wazuh-dashboard && podman rm wazuh-indexer wazuh-manager wazuh-dashboard
set -euo pipefail

WAZUH_VERSION="${WAZUH_VERSION:-4.9.0}"
WAZUH_PASS="${WAZUH_PASS:-SecretPassword123!}"

echo "==> Deploying Wazuh $WAZUH_VERSION all-in-one via podman..."
echo "    This may take a few minutes (downloading ~2 GB of images)..."

# Check podman
if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: podman not found. Install it first: rpm-ostree install podman && reboot"
    exit 1
fi

# Clean up previous deployment if exists
podman stop wazuh-dashboard wazuh-manager wazuh-indexer 2>/dev/null || true
podman rm wazuh-dashboard wazuh-manager wazuh-indexer 2>/dev/null || true

# Create pod for networking
podman pod create --name wazuh-pod -p 443:5601 2>/dev/null || true

# Indexer
echo "==> Starting Wazuh indexer..."
podman run -d --name wazuh-indexer --pod wazuh-pod \
    -e INDEXER_USERNAME=admin \
    -e INDEXER_PASSWORD="$WAZUH_PASS" \
    "wazuh/wazuh-indexer:${WAZUH_VERSION}"

# Manager
echo "==> Starting Wazuh manager..."
podman run -d --name wazuh-manager --pod wazuh-pod \
    -e INDEXER_USERNAME=admin \
    -e INDEXER_PASSWORD="$WAZUH_PASS" \
    -e API_USERNAME=wazuh-wui \
    -e API_PASSWORD="$WAZUH_PASS" \
    "wazuh/wazuh-manager:${WAZUH_VERSION}"

# Dashboard
echo "==> Starting Wazuh dashboard..."
podman run -d --name wazuh-dashboard --pod wazuh-pod \
    -e INDEXER_USERNAME=admin \
    -e INDEXER_PASSWORD="$WAZUH_PASS" \
    -e DASHBOARD_USERNAME=kibanaserver \
    -e DASHBOARD_PASSWORD="$WAZUH_PASS" \
    -e API_USERNAME=wazuh-wui \
    -e API_PASSWORD="$WAZUH_PASS" \
    "wazuh/wazuh-dashboard:${WAZUH_VERSION}"

echo ""
echo "==> Wazuh is deploying (indexer takes ~2 min to initialise)."
echo "    Dashboard:  https://localhost"
echo "    Login:      admin / $WAZUH_PASS"
echo ""
echo "    Check status:  podman logs wazuh-indexer"
echo "    Clean up:      podman pod rm -f wazuh-pod"

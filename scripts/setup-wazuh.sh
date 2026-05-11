#!/bin/bash
# setup-wazuh.sh — deploys Wazuh all-in-one via podman for SOC/SIEM learning
# Optional lab tool — NOT part of automated bootstrap.
# Clean up: podman pod rm -f wazuh-pod
set -euo pipefail

WAZUH_VERSION="${WAZUH_VERSION:-4.9.0}"
WAZUH_PASS="${WAZUH_PASS:-WazuhLab123!}"

echo "==> Deploying Wazuh ${WAZUH_VERSION} (indexer + manager + dashboard)..."
echo "    Downloading images (~2 GB total, may take several minutes)..."

# Clean up previous deployment
podman pod rm -f wazuh-pod 2>/dev/null || true

# Create pod
podman pod create --name wazuh-pod -p 443:5601

# Indexer
echo "==> Starting indexer..."
podman run -d --name wazuh-indexer --pod wazuh-pod \
    -e INDEXER_USERNAME=admin \
    -e INDEXER_PASSWORD="$WAZUH_PASS" \
    "wazuh/wazuh-indexer:${WAZUH_VERSION}"

# Manager
echo "==> Starting manager..."
podman run -d --name wazuh-manager --pod wazuh-pod \
    -e INDEXER_USERNAME=admin \
    -e INDEXER_PASSWORD="$WAZUH_PASS" \
    -e API_USERNAME=wazuh-wui \
    -e API_PASSWORD="$WAZUH_PASS" \
    "wazuh/wazuh-manager:${WAZUH_VERSION}"

# Dashboard
echo "==> Starting dashboard..."
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
echo "    Check progress: podman logs -f wazuh-indexer"
echo "    Dashboard:      https://localhost  (accept self-signed cert)"
echo "    Login:          admin / ${WAZUH_PASS}"
echo ""
echo "    Clean up:       podman pod rm -f wazuh-pod"

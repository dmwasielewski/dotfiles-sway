#!/bin/bash
# setup-misp.sh — deploys MISP (Malware Information Sharing Platform) via podman
# Threat Intelligence Platform for SOC learning.
# Clean up: podman rm -f misp misp-db
set -euo pipefail

MISP_PASS="${MISP_PASS:-MispLab123!}"

echo "==> Deploying MISP (Threat Intelligence Platform)..."
echo "    Downloading images (~1.5 GB, may take several minutes)..."

# Clean up
podman rm -f misp misp-db 2>/dev/null || true
podman pod rm -f misp-pod 2>/dev/null || true

podman pod create --name misp-pod -p 8443:443

# Database
echo "==> Starting database..."
podman run -d --name misp-db --pod misp-pod \
    -e MYSQL_ROOT_PASSWORD="$MISP_PASS" \
    -e MYSQL_DATABASE=misp \
    -e MYSQL_USER=misp \
    -e MYSQL_PASSWORD="$MISP_PASS" \
    docker.io/mysql:8

# MISP
echo "==> Starting MISP..."
podman run -d --name misp --pod misp-pod \
    -e "MISP_BASEURL=https://localhost:8443" \
    -e "MISP_ADMIN_EMAIL=admin@lab.local" \
    -e "MISP_ADMIN_PASSPHRASE=$MISP_PASS" \
    -e "MYSQL_HOST=127.0.0.1" \
    -e "MYSQL_USER=misp" \
    -e "MYSQL_PASSWORD=$MISP_PASS" \
    -e "MYSQL_DATABASE=misp" \
    docker.io/coolacid/misp-docker:latest

echo ""
echo "==> MISP is initialising (database setup takes ~5 minutes)..."
echo "    Check progress: podman logs -f misp"
echo "    Web UI:         https://localhost:8443"
echo "    Login:          admin@lab.local / ${MISP_PASS}"
echo ""
echo "    Clean up:       podman pod rm -f misp-pod"

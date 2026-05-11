#!/bin/bash
# setup-thehive-cortex.sh — deploys TheHive (case management) + Cortex (analysis)
# Advanced SOC lab — incident response automation.
# Requires: podman, ~4 GB disk space
# Clean up: podman pod rm -f soc-pod
set -euo pipefail

PASS="${PASS:-SocLab123!}"

echo "==> Deploying TheHive + Cortex (SOC automation stack)..."
echo "    Downloading images (~2 GB, may take several minutes)..."

# Clean up
podman pod rm -f soc-pod 2>/dev/null || true

podman pod create --name soc-pod \
    -p 9000:9000 \
    -p 9001:9001

# Elasticsearch (shared backend)
echo "==> Starting Elasticsearch..."
podman run -d --name elasticsearch --pod soc-pod \
    -e "discovery.type=single-node" \
    -e "xpack.security.enabled=false" \
    -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
    docker.io/elasticsearch:8.17.0

# Cortex
echo "==> Starting Cortex..."
podman run -d --name cortex --pod soc-pod \
    -e "JAVA_OPTS=-Xms512m -Xmx512m" \
    -e "cortex.http.port=9001" \
    docker.io/strangebee/cortex:latest

# TheHive
echo "==> Starting TheHive..."
podman run -d --name thehive --pod soc-pod \
    -e "JAVA_OPTS=-Xms512m -Xmx512m" \
    -e "thehive.http.port=9000" \
    docker.io/strangebee/thehive:latest

echo ""
echo "==> SOC automation stack is deploying (~3 minutes)..."
echo "    TheHive:  http://localhost:9000"
echo "    Cortex:   http://localhost:9001"
echo ""
echo "    First-time setup:"
echo "      TheHive  → create admin account on first visit"
echo "      Cortex   → create admin account, then generate API key"
echo "      TheHive  → Settings → Cortex → add server with API key"
echo ""
echo "    Clean up:  podman pod rm -f soc-pod"

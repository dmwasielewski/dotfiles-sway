#!/bin/bash
# setup-splunk.sh — runs Splunk Enterprise (free trial) in a podman container for learning
# Optional lab tool for SIEM learning — NOT part of automated bootstrap.
# Splunk free license: 500 MB/day indexing, resets after 60-day trial.
# Clean up:  podman rm -f splunk
set -euo pipefail

SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-SplunkLab123!}"

echo "==> Starting Splunk Enterprise (free) via podman..."
echo "    Downloading image + starting container (may take 2-3 minutes)..."

# Remove old container if exists
podman rm -f splunk 2>/dev/null || true

podman run -d --name splunk \
    -p 8000:8000 \
    -e "SPLUNK_START_ARGS=--accept-license" \
    -e "SPLUNK_PASSWORD=${SPLUNK_PASSWORD}" \
    -e "SPLUNK_LICENSE_URI=Free" \
    splunk/splunk:latest

echo ""
echo "==> Splunk is starting (initial setup takes ~2 minutes)..."
echo "    Check logs:  podman logs -f splunk"
echo "    Web UI:      http://localhost:8000"
echo "    Login:       admin / ${SPLUNK_PASSWORD}"
echo ""
echo "    To stop:     podman stop splunk"
echo "    To start:    podman start splunk"
echo "    To remove:   podman rm -f splunk"

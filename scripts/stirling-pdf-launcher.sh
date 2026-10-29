#!/bin/bash
# WebKitGTK 2.54.1 crashes in Clipboard::formats for unavailable GTK targets.
# XWayland alone is insufficient: normalize GTK NULL/-1 target callbacks below.
# TLS remains verified; no global GTK library or clipboard contents are changed.
set -euo pipefail
# Upstream's FileMonitor retries forever when this root directory is missing.
mkdir -p "$HOME/.config/Stirling-PDF/pipeline/watchedFolders"
export GDK_BACKEND="${STIRLING_GDK_BACKEND:-x11}"
if [[ -z "${SSL_CERT_FILE:-}" && -r /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ]]; then
    export SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
fi
shim="$HOME/.local/lib/stirling-pdf/clipboard-compat.so"
if [[ -r "$shim" ]]; then
    export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}"
else
    echo 'WARNING: Stirling PDF clipboard compatibility shim missing; run setup-stirling-runtime.sh.' >&2
fi
exec "$HOME/.local/opt/stirling-pdf/current/usr/bin/Stirling-PDF" "$@"

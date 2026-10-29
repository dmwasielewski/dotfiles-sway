#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.local/opt/stirling-pdf/current/usr/bin" "$tmp/.local/lib/stirling-pdf"
gcc -shared -fPIC "$repo/scripts/native/stirling-clipboard.c" -ldl -o "$tmp/.local/lib/stirling-pdf/clipboard-compat.so"
cat > "$tmp/.local/opt/stirling-pdf/current/usr/bin/Stirling-PDF" <<'BIN'
#!/bin/bash
printf '%s\n' "$GDK_BACKEND" "${SSL_CERT_FILE:-}" "${LD_PRELOAD:-}" "$@"
BIN
chmod +x "$tmp/.local/opt/stirling-pdf/current/usr/bin/Stirling-PDF"
result=$(HOME="$tmp" SSL_CERT_FILE=/tmp/explicit-ca.pem bash "$repo/scripts/stirling-pdf-launcher.sh" '/tmp/file with spaces.pdf')
expected=$(printf '%s\n' x11 /tmp/explicit-ca.pem "$tmp/.local/lib/stirling-pdf/clipboard-compat.so" '/tmp/file with spaces.pdf')
[[ "$result" == "$expected" ]]
echo 'PASS: launcher selects XWayland, loads the GTK shim, preserves explicit CA and PDF arguments'

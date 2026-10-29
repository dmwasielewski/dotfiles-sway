#!/bin/bash
set -eu
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
printf broken > "$sandbox/package.rpm"
python3 - "$sandbox/release.json" <<'PY'
import json,sys
json.dump({'tag_name':'v0.0.0','assets':[{'name':'Stirling-PDF-linux-x86_64.rpm','browser_download_url':'https://github.com/Stirling-Tools/Stirling-PDF/releases/download/v0.0.0/Stirling-PDF-linux-x86_64.rpm','digest':'sha256:'+'0'*64}]},open(sys.argv[1],'w'))
PY
if HOME="$sandbox" DOTFILES="$repo" STIRLING_RELEASE_JSON="$sandbox/release.json" STIRLING_RPM="$sandbox/package.rpm" bash "$repo/scripts/setup-stirling-pdf.sh" > "$sandbox/log" 2>&1; then
 echo 'FAIL: corrupt package accepted'; exit 1
fi
rg -q 'package.rpm: FAILED' "$sandbox/log"
test ! -e "$sandbox/.local/bin/stirling-pdf"
rg -q '^STIRLING_PDF_INSTALLED=failed$' "$sandbox/.dotfiles-install-state"
echo 'PASS: corrupt package rejected before installation'

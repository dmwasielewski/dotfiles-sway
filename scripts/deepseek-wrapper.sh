#!/bin/bash
set -euo pipefail

name="$(basename "$0")"
real="$HOME/.npm-global/lib/node_modules/deepseek-tui/bin/$name.js"

if [[ ! -x "$real" ]]; then
    echo "$name wrapper: real binary not found: $real" >&2
    exit 127
fi

export NO_ANIMATIONS=1
exec "$real" --no-mouse-capture "$@"

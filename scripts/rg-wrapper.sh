#!/bin/bash
# Prefer the distro-packaged ripgrep over vendored copies from other tools.

set -euo pipefail

if [[ -x /usr/bin/rg ]]; then
    exec /usr/bin/rg "$@"
fi

printf 'rg: command not found. Install ripgrep.\n' >&2
exit 127

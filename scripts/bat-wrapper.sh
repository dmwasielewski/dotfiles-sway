#!/bin/bash
# Cross-distro bat entry point. Ubuntu may package the binary as batcat.

set -euo pipefail

if [[ -x /usr/bin/bat ]]; then
    exec /usr/bin/bat "$@"
fi

if [[ -x /usr/bin/batcat ]]; then
    exec /usr/bin/batcat "$@"
fi

printf 'bat: command not found. Install bat or batcat.\n' >&2
exit 127

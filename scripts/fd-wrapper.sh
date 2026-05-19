#!/bin/bash
# Cross-distro fd entry point. Ubuntu may package the binary as fdfind.

set -euo pipefail

if [[ -x /usr/bin/fd ]]; then
    exec /usr/bin/fd "$@"
fi

if [[ -x /usr/bin/fdfind ]]; then
    exec /usr/bin/fdfind "$@"
fi

printf 'fd: command not found. Install fd-find.\n' >&2
exit 127

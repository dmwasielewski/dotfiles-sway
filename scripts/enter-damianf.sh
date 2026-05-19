#!/bin/bash
# Enter Fedora dev toolbox with the short, user-facing command: damianf

set -euo pipefail

if [[ $# -eq 0 ]]; then
    exec toolbox enter damianf
fi

exec toolbox run --container damianf "$@"

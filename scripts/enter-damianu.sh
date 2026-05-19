#!/bin/bash
# Enter Ubuntu dev distrobox with the short, user-facing command: damianu

set -euo pipefail

if [[ $# -eq 0 ]]; then
    exec distrobox enter damianu
fi

exec distrobox enter damianu -- "$@"

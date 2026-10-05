#!/bin/bash
# Keep AppImage's bundled libraries out of the native Fedora client.
set -euo pipefail
CLIENT="$HOME/.local/opt/onedrive-client/current"
exec env -u LD_PRELOAD LD_LIBRARY_PATH="$CLIENT/lib" "$CLIENT/onedrive" "$@"

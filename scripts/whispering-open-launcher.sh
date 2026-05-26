#!/bin/bash
# Launch Whispering Open with the WebKit/GTK settings required on Damian's Sway session.

set -euo pipefail

export GDK_BACKEND=x11
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export LIBGL_ALWAYS_SOFTWARE=1

exec "$HOME/.local/bin/whispering-open" "$@"

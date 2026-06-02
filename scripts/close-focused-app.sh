#!/bin/bash
# super+Shift+q — kill the ENTIRE focused application, not just its window.
# A window "close" only asks one surface to go away; multi-process apps
# (Chromium/Electron/Tauri: Vivaldi, Obsidian, VSCode, whispering-open…) keep a
# master + helper processes alive after that, and some catch SIGTERM to hide to a
# tray instead of quitting. So we terminate the focused process AND its whole
# subtree, then escalate to SIGKILL for anything that ignored SIGTERM — nothing is
# left running in the background. (super+q stays Sway's `kill` = close one window.)
set -uo pipefail

pid="$(swaymsg -t get_tree 2>/dev/null \
    | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused == true) | .pid // empty')"

if [[ -z "$pid" || "$pid" == "null" ]]; then
    swaymsg kill          # no PID (e.g. some XWayland surfaces) — fall back to window kill
    exit 0
fi

# Collect the focused process and every descendant (renderers, helpers, zygotes).
collect_tree() {
    local p="$1" c
    printf '%s\n' "$p"
    for c in $(pgrep -P "$p" 2>/dev/null); do collect_tree "$c"; done
}
mapfile -t pids < <(collect_tree "$pid")

kill -TERM "${pids[@]}" 2>/dev/null || true    # graceful first: apps may save state
for _ in 1 2 3 4 5 6; do                       # allow ~1.5s for a clean exit
    kill -0 "$pid" 2>/dev/null || exit 0
    sleep 0.25
done
kill -KILL "${pids[@]}" 2>/dev/null || true    # caught SIGTERM / hid to tray → force

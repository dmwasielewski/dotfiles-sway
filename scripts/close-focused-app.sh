#!/bin/bash
# Fully close the focused application by terminating its process — not just the
# window. Chromium/Electron apps (Vivaldi, Obsidian, VSCode…) keep a master
# process alive after a normal window close, so the app keeps running (and an
# update can't take effect until it's gone). SIGTERM is graceful: apps can still
# catch it and save state / restore session on next launch.
set -uo pipefail

pid="$(swaymsg -t get_tree 2>/dev/null \
    | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused == true) | .pid // empty')"

if [[ -n "$pid" && "$pid" != "null" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
else
    # No PID available (e.g. some XWayland surfaces) — fall back to Sway's own
    # window kill so the shortcut still does something sensible.
    swaymsg kill
fi

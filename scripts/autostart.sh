#!/bin/bash

# Main browser: Firefox (Fedora Sway Atomic's default browser, shipped in the
# base image). It is pinned to ws2 by the assign rule in sway/config.
firefox &
disown
sleep 4

# Obsidian is no longer part of autostart — launched on demand, no workspace.

# ChatGPT desktop app (ChatGPT + Work + Codex). Pinned to ws4 by the assign
# rules in sway/config — see the note there about XWayland class vs app_id.
chatgpt &
disown

# Claude Desktop, pinned to ws5. The wrapper adds --password-store=gnome-libsecret.
"$HOME/.local/bin/claude-desktop" &
disown

# Personal Windows desktop, pinned to ws6; the launcher avoids duplicates.
"$HOME/dotfiles-sway/scripts/launch-win11edu-damian.sh" &
disown

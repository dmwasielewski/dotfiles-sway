#!/bin/bash

# Main browser: Firefox (Fedora Sway Atomic's default browser, shipped in the
# base image). It is pinned to ws2 by the assign rule in sway/config.
firefox &
disown
sleep 4

flatpak run md.obsidian.Obsidian &
disown

# ChatGPT desktop app (ChatGPT + Work + Codex). Pinned to ws5 by the assign
# rules in sway/config — see the note there about XWayland class vs app_id.
chatgpt &
disown

# Host KVM manager, pinned to ws6. Opening the GUI does not start guests.
virt-manager --connect qemu:///system &
disown

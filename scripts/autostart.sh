#!/bin/bash

# Main browser: Firefox (Fedora Sway Atomic's default browser, shipped in the
# base image). It is pinned to ws2 by the assign rule in sway/config.
firefox &
disown
sleep 4

flatpak run md.obsidian.Obsidian &
disown

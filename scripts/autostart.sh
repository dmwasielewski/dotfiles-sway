#!/bin/bash

# Fix Vivaldi crash flags
python3 - << 'PYEOF'
import json, os, glob
profiles = glob.glob(os.path.expanduser(
    "~/.var/app/com.vivaldi.Vivaldi/config/vivaldi/*/Preferences"
))
for path in profiles:
    try:
        with open(path) as f:
            p = json.load(f)
        p.setdefault('profile', {})['exit_type'] = 'Normal'
        p['profile']['exited_cleanly'] = True
        with open(path, 'w') as f:
            json.dump(p, f)
    except Exception:
        pass
PYEOF

# Wait for Wayland to be fully ready
sleep 2

# Start Vivaldi main first — let it fully initialise
flatpak run com.vivaldi.Vivaldi &
sleep 4

# Now start PWAs — Vivaldi already running, PWAs open in new windows
flatpak run com.vivaldi.Vivaldi --app=https://chatgpt.com --profile-directory="ChatGPT" &
sleep 2
flatpak run com.vivaldi.Vivaldi --app=https://claude.ai --profile-directory="Claude" &
sleep 2

# Obsidian last
flatpak run md.obsidian.Obsidian &

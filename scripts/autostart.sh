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

sleep 6

flatpak run com.vivaldi.Vivaldi &
disown
sleep 4

flatpak run com.vivaldi.Vivaldi --app=https://chatgpt.com --profile-directory="ChatGPT" &
disown
sleep 2

flatpak run com.vivaldi.Vivaldi --app=https://claude.ai --profile-directory="Claude" &
disown
sleep 2

flatpak run md.obsidian.Obsidian &
disown

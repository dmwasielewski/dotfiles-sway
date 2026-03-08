#!/bin/bash
# Fix Vivaldi crash flags before launch — prevents Session Recovery dialog
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

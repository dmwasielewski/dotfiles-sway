#!/bin/bash
# Fix Vivaldi crash flags before launch — prevents Session Recovery dialog
python3 - << 'PYEOF'
import glob
import json
import os
import shutil
import tempfile

profiles = glob.glob(os.path.expanduser(
    "~/.var/app/com.vivaldi.Vivaldi/config/vivaldi/*/Preferences"
))
backup_suffix = ".bak-before-dotfiles"
for path in profiles:
    try:
        with open(path, encoding="utf-8") as f:
            p = json.load(f)
        p.setdefault('profile', {})['exit_type'] = 'Normal'
        p['profile']['exited_cleanly'] = True
        backup_path = path + backup_suffix
        if not os.path.exists(backup_path):
            shutil.copy2(path, backup_path)

        fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), prefix="Preferences.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(p, f)
            os.replace(tmp_path, path)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as exc:
        print(f"WARNING: failed to repair {path}: {exc}", file=os.sys.stderr)
PYEOF

#!/usr/bin/env python3
"""Restore validated opt-in homelab files from harvested encrypted-vault staging."""
import importlib.util
import os
from pathlib import Path
import sys


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), Path(__file__).with_name(name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def restore(source, dest):
    if not source.exists():
        print('No staged homelab configuration; existing files preserved')
        return
    if source.is_symlink() or not source.is_dir():
        raise ValueError('Expected a regular staged directory')
    files = []
    def add(name):
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Expected a regular private configuration file')
        files.append(path)
        return path
    if (source / 'proxmox-client.json').exists() or (source / 'proxmox-client.json').is_symlink():
        policy = add('proxmox-client.json')
        data, _ = module('proxmox-client').policy(policy)
        add(data['ca_file'])
    if (source / 'nordvpn-homelab.json').exists() or (source / 'nordvpn-homelab.json').is_symlink():
        module('nordvpn-homelab').load_policy(add('nordvpn-homelab.json'))
    if (source / 'tailscale-accept-routes').exists() or (source / 'tailscale-accept-routes').is_symlink():
        if add('tailscale-accept-routes').read_text().strip() not in ('true', 'false'):
            raise ValueError('Invalid subnet-route preference')
    if len({p.name for p in files}) != len(files):
        raise ValueError('Duplicate staged filenames')
    if dest.is_symlink():
        raise ValueError('Refusing a destination directory symlink')
    # Validate every source and conflict before making any destination changes.
    for path in files:
        target = dest / path.name
        if target.is_symlink() or (target.exists() and target.read_bytes() != path.read_bytes()):
            raise ValueError('Existing private configuration differs; resolve before retrying')
    if not files:
        print('No recognized staged homelab files; existing files preserved')
        return
    dest.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path in files:
        target = dest / path.name
        if not target.exists():
            # Exclusive creation prevents overwriting a concurrently created file.
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'wb') as out:
                out.write(path.read_bytes())
        target.chmod(0o600)
    print('Validated homelab configuration restored; no account credentials printed')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('Usage: restore-homelab-config.py STAGED_CONFIG DESTINATION')
        restore(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError):
        print('Homelab restore failed; check staged policy, CA pin and destination conflicts', file=sys.stderr)
        sys.exit(1)

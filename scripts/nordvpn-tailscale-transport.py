#!/usr/bin/env python3
"""Preserve Tailscale transport through NordVPN's changing firewall chain.

No user input or private policy is read. Only a tagged Tailscale-underlay mark rule is managed. Runtime copy is root-owned, outside the home directory.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading

TAG = 'dotfiles-tailscale-nord-transport'
NFT = '/usr/sbin/nft'
SERVICE = 'nordvpn-tailscale-transport.service'


def command(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=5)


def rules():
    result = command([NFT, '-j', 'list', 'chain', 'inet', 'nordvpn', 'output'])
    if result.returncode:
        if 'No such file or directory' in result.stderr:
            return None
        raise RuntimeError('Cannot read NordVPN output chain')
    return [entry['rule'] for entry in json.loads(result.stdout)['nftables']
            if 'rule' in entry]


def remove_owned(items):
    for rule in items or []:
        if rule.get('comment', '').startswith(TAG + '-'):
            result = command([NFT, 'delete', 'rule', 'inet', 'nordvpn', 'output',
                              'handle', str(rule['handle'])])
            if result.returncode:
                raise RuntimeError('Cannot remove managed transport exception')


def nord_mark(items):
    # Read the daemon's own packet/connection-mark allow rule, not user config.
    for rule in items or []:
        expr = rule.get('expr', [])
        if not any('mangle' in e and e['mangle'].get('key') == {'ct': {'key': 'mark'}} for e in expr):
            continue
        for entry in expr:
            match = entry.get('match', {})
            value = match.get('right')
            if (match.get('op') == '==' and match.get('left') == {'meta': {'key': 'mark'}}
                    and type(value) is int and 0 < value <= 0xffffffff
                    and value & 0xff0000 != 0x80000):
                return value
    raise RuntimeError('Cannot identify NordVPN connection mark')


def reconcile(active):
    items = rules()
    if items is None:
        return 'idle'
    if not active:
        remove_owned(items)
        return 'idle'
    mark = nord_mark(items)
    comment = TAG + '-' + str(mark)
    if items and items[0].get('comment') == comment:
        return 'ready'
    remove_owned(items)
    result = command([NFT, 'insert', 'rule', 'inet', 'nordvpn', 'output',
                      'meta', 'mark', '&', '0xff0000', '==', '0x80000',
                      'ct', 'mark', 'set', str(mark), 'counter', 'accept',
                      'comment', comment])
    if result.returncode:
        raise RuntimeError('Cannot preserve Tailscale transport connection mark')
    return 'updated'


def install():
    source = Path(__file__).resolve()
    unit = Path('/etc/dotfiles') / SERVICE
    if source != Path('/etc/dotfiles/nordvpn-tailscale-transport.py'):
        raise RuntimeError('Install requires the protected copy')
    for item in (source, unit, source.parent):
        metadata = item.stat()
        if metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise RuntimeError('Install files must be root-owned and not user-writable')
    target = Path('/etc/systemd/system') / SERVICE
    shutil.copyfile(unit, target)
    os.chown(target, 0, 0)
    os.chmod(target, 0o644)
    for args in [('daemon-reload',), ('enable', '--now', SERVICE), ('restart', SERVICE)]:
        result = command(['systemctl', *args])
        if result.returncode:
            raise RuntimeError('Cannot activate transport compatibility service')
    print('Root-owned Tailscale transport compatibility service installed')


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2 or sys.argv[1] not in ('install', 'watch', 'check'):
        print('Requires root: nordvpn-tailscale-transport.py install|watch|check', file=sys.stderr)
        return 2
    if sys.argv[1] == 'install':
        install()
        return 0
    if sys.argv[1] == 'check':
        state = reconcile(Path('/sys/class/net/tailscale0').exists())
        print('Local transport exception: ' + state)
        return 0
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    try:
        while not stop.is_set():
            state = reconcile(Path('/sys/class/net/tailscale0').exists())
            if state == 'updated':
                print('Restored local Tailscale transport exceptions', flush=True)
            stop.wait(1)
    finally:
        remove_owned(rules())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(type(error).__name__ + ': local transport compatibility operation failed', file=sys.stderr)
        sys.exit(1)

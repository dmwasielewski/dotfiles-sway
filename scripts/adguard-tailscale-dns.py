#!/usr/bin/env python3
"""Preserve local Tailscale DNS through AdGuard's changing NAT chain.

No user input or private policy is read. Only tagged UDP/TCP port-53 rules
for Quad100 are managed. Runtime copy is root-owned, outside the home directory.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading

TAG = 'dotfiles-tailscale-local-dns'
QUAD = '100.100.100.100'
NFT = '/usr/sbin/nft'
SERVICE = 'adguard-tailscale-dns.service'


def command(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=5)


def rules():
    result = command([NFT, '-j', 'list', 'chain', 'ip', 'nat', 'AGCLI'])
    if result.returncode:
        if 'No such file or directory' in result.stderr:
            return None
        raise RuntimeError('Cannot read AdGuard NAT chain')
    return [entry['rule'] for entry in json.loads(result.stdout)['nftables']
            if 'rule' in entry]


def remove_owned(items):
    for rule in items or []:
        if rule.get('comment', '').startswith(TAG + '-'):
            result = command([NFT, 'delete', 'rule', 'ip', 'nat', 'AGCLI',
                              'handle', str(rule['handle'])])
            if result.returncode:
                raise RuntimeError('Cannot remove managed DNS exception')


def reconcile(active):
    items = rules()
    if items is None:
        return 'idle'
    if not active:
        remove_owned(items)
        return 'idle'
    # Rebuild only our two rules if missing or moved behind AdGuard DNS redirect.
    # A plain presence check is insufficient after a vendor chain rebuild.
    if [r.get('comment') for r in items[:2]] == [TAG + '-tcp', TAG + '-udp']:
        return 'ready'
    remove_owned(items)
    for protocol in ('udp', 'tcp'):
        result = command([NFT, 'insert', 'rule', 'ip', 'nat', 'AGCLI',
                          'ip', 'daddr', QUAD, protocol, 'dport', '53',
                          'return', 'comment', TAG + '-' + protocol])
        if result.returncode:
            raise RuntimeError('Cannot install local Tailscale DNS exception')
    return 'updated'


def install():
    source = Path(__file__).resolve()
    unit = Path('/etc/dotfiles') / SERVICE
    if source != Path('/etc/dotfiles/adguard-tailscale-dns.py'):
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
            raise RuntimeError('Cannot activate DNS compatibility service')
    print('Root-owned Tailscale DNS compatibility service installed')


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2 or sys.argv[1] not in ('install', 'watch', 'check'):
        print('Requires root: adguard-tailscale-dns.py install|watch|check', file=sys.stderr)
        return 2
    if sys.argv[1] == 'install':
        install()
        return 0
    if sys.argv[1] == 'check':
        state = reconcile(Path('/sys/class/net/tailscale0').exists())
        print('Local DNS exception: ' + state)
        return 0
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    try:
        while not stop.is_set():
            state = reconcile(Path('/sys/class/net/tailscale0').exists())
            if state == 'updated':
                print('Restored local Tailscale DNS exceptions', flush=True)
            stop.wait(1)
    finally:
        remove_owned(rules())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(type(error).__name__ + ': local DNS compatibility operation failed', file=sys.stderr)
        sys.exit(1)

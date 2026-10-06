#!/usr/bin/env python3
"""Apply/check an explicit private NordVPN IPv4 exception policy.

Never changes firewall/routing, VPN connection, DNS, or existing exceptions.
"""
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PRIVATE = tuple(ipaddress.ip_network(n) for n in
                ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))
TAILSCALE = ipaddress.ip_network('100.64.0.0/10')


def policy_path():
    return Path(os.environ.get('DOTFILES_NORDVPN_POLICY',
                str(Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
                    / 'dotfiles/nordvpn-homelab.json')))


def load_policy(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or set(data) != {'subnets'}:
        raise ValueError('Expected an object containing only subnets')
    if not isinstance(data['subnets'], list) or not data['subnets']:
        raise ValueError('Expected a nonempty subnet list')
    nets = []
    for value in data['subnets']:
        if not isinstance(value, str):
            raise ValueError('Subnet entries must be strings')
        net = ipaddress.ip_network(value, strict=True)
        if net.version != 4 or not (
            any(net.subnet_of(n) for n in PRIVATE) or
            (net.prefixlen == 32 and net.subnet_of(TAILSCALE))
        ):
            raise ValueError('Only private LAN networks or individual Tailscale IPv4 hosts are supported')
        if net not in nets:
            nets.append(net)
    return nets


def command(*args):
    result = subprocess.run(['nordvpn', *args], capture_output=True, text=True,
                            timeout=30, check=False)
    if result.returncode:
        # CLI output may contain private addresses/account information.
        raise RuntimeError('NordVPN command failed; check login, daemon and group membership')
    return result.stdout


def current():
    text = command('settings')
    nets = []
    if 'Allowlisted subnets:' in text:
        tail = text.split('Allowlisted subnets:', 1)[1]
        for line in tail.splitlines():
            if line and not line[0].isspace():
                break
            for value in re.findall(r'\b(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}\b', line):
                net = ipaddress.ip_network(value)
                if net.version == 4:
                    nets.append(net)
    return nets


def covered(net, existing):
    return any(net.subnet_of(n) for n in existing)


def apply(nets):
    existing = current()
    added = []
    try:
        for net in nets:
            if not covered(net, existing):
                command('allowlist', 'add', 'subnet', str(net))
                added.append(net)
                existing.append(net)
        if not all(covered(n, current()) for n in nets):
            raise RuntimeError('NordVPN did not retain the requested exceptions')
    except Exception:
        rollback_failed = False
        for net in reversed(added):
            try:
                command('allowlist', 'remove', 'subnet', str(net))
            except Exception:
                rollback_failed = True
        if rollback_failed:
            raise RuntimeError('Application failed and rollback was incomplete; review NordVPN settings') from None
        raise
    return len(added)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('apply', 'check'):
        print('Usage: nordvpn-homelab.py apply|check', file=sys.stderr)
        return 2
    path = policy_path()
    if not path.exists():
        print('NordVPN homelab policy not configured; existing settings unchanged')
        return 0
    try:
        nets = load_policy(path)
        if sys.argv[1] == 'apply':
            count = apply(nets)
            print(f'NordVPN homelab exceptions verified; {count} added')
        elif not all(covered(n, current()) for n in nets):
            print('NordVPN homelab policy has missing exceptions', file=sys.stderr)
            return 1
        else:
            print('NordVPN homelab exceptions present (reachability is a separate test)')
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired):
        print('Cannot validate/apply NordVPN homelab policy; check private config and NordVPN readiness', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

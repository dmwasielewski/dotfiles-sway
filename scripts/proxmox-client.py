#!/usr/bin/env python3
"""Opt-in Proxmox client trust; never downloads or accepts an unpinned CA."""
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import time

ANCHOR = Path('/etc/pki/ca-trust/source/anchors/dotfiles-proxmox-ca.pem')
HOSTS = Path('/etc/hosts')
BEGIN = '# BEGIN dotfiles-proxmox-client'
END = '# END dotfiles-proxmox-client'
PRIVATE = [ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]


def fingerprint(pem):
    if pem.count('-----BEGIN CERTIFICATE-----') != 1 or 'PRIVATE KEY' in pem:
        raise ValueError('Expected exactly one public certificate')
    return hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()


def policy(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or set(data) != {'hostname', 'address', 'ca_file', 'sha256'}:
        raise ValueError('Expected hostname, address, ca_file, sha256')
    if not all(isinstance(v, str) for v in data.values()):
        raise ValueError('All policy fields must be strings')
    host = data['hostname']
    labels = host.split('.')
    if len(host) > 253 or len(labels) < 2 or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', v) for v in labels):
        raise ValueError('Expected a lowercase DNS hostname')
    addr = ipaddress.ip_address(data['address'])
    if addr.version != 4 or not any(addr in n for n in PRIVATE):
        raise ValueError('Expected a private IPv4 address')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]*\.(pem|crt)', data['ca_file']):
        raise ValueError('CA must be a file beside the private policy')
    ca = path.parent / data['ca_file']
    if ca.is_symlink():
        raise ValueError('CA symlinks are not accepted')
    pem = ca.read_text()
    expected = data['sha256'].replace(':', '').lower()
    if not re.fullmatch(r'[0-9a-f]{64}', expected) or fingerprint(pem) != expected:
        raise ValueError('CA fingerprint does not match the authenticated pin')
    cert = ssl._ssl._test_decode_cert(str(ca.resolve()))
    now = time.time()
    if not ssl.cert_time_to_seconds(cert['notBefore']) <= now < ssl.cert_time_to_seconds(cert['notAfter']):
        raise ValueError('CA is not currently valid')
    return data, pem


def hosts_content(original, data):
    lines = original.splitlines(); keep = []; inside = False; seen = False
    for line in lines:
        if line == BEGIN:
            if inside or seen: raise ValueError('Duplicate managed hosts block')
            inside = True; seen = True; continue
        if line == END:
            if not inside: raise ValueError('Unexpected hosts block end')
            inside = False; continue
        if not inside: keep.append(line)
    if inside: raise ValueError('Unterminated managed hosts block')
    for line in keep:
        fields = line.split('#', 1)[0].split()
        if len(fields) > 1 and data['hostname'] in fields[1:] and fields[0] != data['address']:
            raise ValueError('Existing hostname mapping conflicts; no changes made')
    return '\n'.join(keep).rstrip('\n') + '\n' + BEGIN + '\n' + data['address'] + ' ' + data['hostname'] + '\n' + END + '\n'


def check(data, pem):
    if not ANCHOR.is_file() or ANCHOR.is_symlink() or fingerprint(ANCHOR.read_text()) != fingerprint(pem):
        raise RuntimeError('CA trust anchor missing or different')
    if ANCHOR.stat().st_uid != 0 or ANCHOR.stat().st_mode & 0o022:
        raise RuntimeError('CA anchor ownership/permissions invalid')
    content = HOSTS.read_text()
    if hosts_content(content, data) != content:
        raise RuntimeError('Managed hostname mapping missing or stale')
    print('Pinned Proxmox CA and hostname configured; test HTTPS separately')


def apply(data, pem):
    if os.geteuid() != 0: raise RuntimeError('Apply requires authenticated administrator access')
    old_hosts = HOSTS.read_text(); new_hosts = hosts_content(old_hosts, data)
    if ANCHOR.is_symlink(): raise RuntimeError('Refusing an anchor symlink')
    existing = ANCHOR.exists()
    if existing and fingerprint(ANCHOR.read_text()) != fingerprint(pem):
        raise RuntimeError('Refusing to replace a different trust anchor')
    try:
        if not existing:
            ANCHOR.write_text(pem)
            os.chown(ANCHOR, 0, 0); os.chmod(ANCHOR, 0o644)
        if new_hosts != old_hosts:
            # Preserve the existing inode, permissions and SELinux label.
            HOSTS.write_text(new_hosts)
        subprocess.run(['/usr/bin/update-ca-trust', 'extract'], check=True, timeout=30)
        check(data, pem)
    except Exception:
        HOSTS.write_text(old_hosts)
        if not existing: ANCHOR.unlink(missing_ok=True)
        subprocess.run(['/usr/bin/update-ca-trust', 'extract'], check=False, timeout=30)
        raise


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('apply', 'check', 'validate'):
        raise ValueError('Usage: proxmox-client.py apply|check|validate PRIVATE_POLICY')
    data, pem = policy(Path(sys.argv[2]))
    if sys.argv[1] == 'apply': apply(data, pem)
    elif sys.argv[1] == 'check': check(data, pem)
    else: print('Private CA fingerprint, validity and policy validated')


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        print('Proxmox client configuration failed; verify policy, pin, CA and administrator access', file=sys.stderr)
        sys.exit(1)

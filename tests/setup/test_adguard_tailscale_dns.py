#!/usr/bin/env python3
"""No real root, nftables, services or network calls."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dnscompat', Path(__file__).resolve().parents[2] / 'scripts/adguard-tailscale-dns.py')
dns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dns)


class FakeNft:
    def __init__(self, items=None):
        self.items = items
        self.calls = []
        self.counter = 20

    def command(self, args):
        self.calls.append(args)
        if args[1:3] == ['-j', 'list']:
            if self.items is None:
                return SimpleNamespace(returncode=1, stdout='', stderr='No such file or directory')
            return SimpleNamespace(returncode=0, stdout=json.dumps({'nftables': [{'rule': r} for r in self.items]}), stderr='')
        if args[1] == 'insert':
            self.counter += 1
            self.items.insert(0, {'handle': self.counter, 'comment': args[-1]})
        elif args[1] == 'delete':
            self.items[:] = [r for r in self.items if r['handle'] != int(args[-1])]
        else:
            raise AssertionError('Unexpected command')
        return SimpleNamespace(returncode=0, stdout='', stderr='')


class Tests(unittest.TestCase):
    def test_absent_chain_is_idle(self):
        nft = FakeNft()
        with patch.object(dns, 'command', nft.command):
            self.assertEqual(dns.reconcile(True), 'idle')
        self.assertEqual(len(nft.calls), 1)

    def test_insert_before_redirect_and_idempotence(self):
        nft = FakeNft([{'handle': 1, 'comment': 'vendor DNS redirect'}])
        with patch.object(dns, 'command', nft.command):
            self.assertEqual(dns.reconcile(True), 'updated')
            self.assertEqual(dns.reconcile(True), 'ready')
        self.assertEqual([r['comment'] for r in nft.items[:2]], [dns.TAG + '-tcp', dns.TAG + '-udp'])
        inserts = [c for c in nft.calls if c[1] == 'insert']
        self.assertEqual(len(inserts), 2)
        self.assertTrue(all(c[3:6] == ['ip', 'nat', 'AGCLI'] for c in inserts))
        self.assertTrue(all(dns.QUAD in c and '53' in c and 'return' in c for c in inserts))

    def test_vendor_restart_and_moved_rules_are_repaired(self):
        nft = FakeNft([{'handle': 1, 'comment': 'vendor'}])
        with patch.object(dns, 'command', nft.command):
            dns.reconcile(True)
            nft.items.insert(0, {'handle': 2, 'comment': 'new vendor redirect'})
            self.assertEqual(dns.reconcile(True), 'updated')
            nft.items[:] = [{'handle': 3, 'comment': 'rebuilt vendor chain'}]
            self.assertEqual(dns.reconcile(True), 'updated')
        self.assertEqual(len(nft.items), 3)
        self.assertEqual(nft.items[-1]['comment'], 'rebuilt vendor chain')

    def test_removes_only_owned_rules_when_tailscale_disappears(self):
        nft = FakeNft([{'handle': 1, 'comment': dns.TAG + '-udp'}, {'handle': 2, 'comment': 'foreign rule'}])
        with patch.object(dns, 'command', nft.command):
            self.assertEqual(dns.reconcile(False), 'idle')
        self.assertEqual(nft.items, [{'handle': 2, 'comment': 'foreign rule'}])

    def test_read_error_does_not_silently_claim_idle(self):
        with patch.object(dns, 'command', return_value=SimpleNamespace(returncode=1, stdout='', stderr='Permission denied')):
            with self.assertRaises(RuntimeError): dns.reconcile(True)

    def test_installer_rejects_repository_or_user_writable_copy(self):
        with patch.object(dns, '__file__', '/tmp/user-script.py'), self.assertRaises(RuntimeError):
            dns.install()
        with patch.object(dns, '__file__', '/etc/dotfiles/adguard-tailscale-dns.py'), \
             patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=1000, st_mode=0o644)), \
             self.assertRaises(RuntimeError):
            dns.install()


if __name__ == '__main__':
    unittest.main()

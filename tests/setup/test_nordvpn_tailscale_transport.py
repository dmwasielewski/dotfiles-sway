#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from test_adguard_tailscale_dns import FakeNft
spec = importlib.util.spec_from_file_location('transport', Path(__file__).resolve().parents[2] / 'scripts/nordvpn-tailscale-transport.py')
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)
def vendor(mark=57841):
    return {'handle': 1, 'expr': [{'match': {'op': '==', 'left': {'meta': {'key': 'mark'}}, 'right': mark}}, {'mangle': {'key': {'ct': {'key': 'mark'}}, 'value': {'meta': {'key': 'mark'}}}}, {'accept': None}]}
class Tests(unittest.TestCase):
    def test_scope_and_idempotence(self):
        original = vendor(); nft = FakeNft([original])
        with patch.object(n, 'command', nft.command):
            self.assertEqual(n.reconcile(True), 'updated')
            self.assertEqual(n.reconcile(True), 'ready')
        inserts = [c for c in nft.calls if c[1] == 'insert']
        self.assertEqual(len(inserts), 1)
        c = inserts[0]
        self.assertEqual(c[3:6], ['inet', 'nordvpn', 'output'])
        self.assertEqual(c[6:12], ['meta', 'mark', '&', '0xff0000', '==', '0x80000'])
        self.assertEqual(c[12:17], ['ct', 'mark', 'set', '57841', 'counter'])
        self.assertEqual(nft.items[-1], original)
    def test_rebuild_and_changed_mark(self):
        nft = FakeNft([vendor()])
        with patch.object(n, 'command', nft.command):
            n.reconcile(True)
            nft.items[:] = [vendor(12345)]
            self.assertEqual(n.reconcile(True), 'updated')
        self.assertEqual(nft.items[0]['comment'], n.TAG + '-12345')
    def test_no_unknown_mark_fallback(self):
        nft = FakeNft([{'handle': 1, 'comment': 'unknown vendor layout'}])
        with patch.object(n, 'command', nft.command), self.assertRaises(RuntimeError):
            n.reconcile(True)
        self.assertFalse(any(c[1] == 'insert' for c in nft.calls))
    def test_missing_chain_and_cleanup_preserves_foreign_rule(self):
        nft = FakeNft()
        with patch.object(n, 'command', nft.command): self.assertEqual(n.reconcile(True), 'idle')
        nft.items = [{'handle': 2, 'comment': n.TAG + '-12345'}, vendor()]
        with patch.object(n, 'command', nft.command): n.reconcile(False)
        self.assertEqual(nft.items, [vendor()])
if __name__ == '__main__': unittest.main()

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess

spec = importlib.util.spec_from_file_location('pve', Path(__file__).resolve().parents[2] / 'scripts/proxmox-client.py')
pve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pve)
D = {'hostname': 'pve.example.home', 'address': '192.168.50.10'}

class Tests(unittest.TestCase):
    def test_preserves_and_is_idempotent(self):
        original = '127.0.0.1 localhost\n# Keep this\n192.168.50.20 other.home\n'
        new = pve.hosts_content(original, D)
        self.assertTrue(new.startswith(original))
        self.assertEqual(pve.hosts_content(new, D), new)

    def test_conflict(self):
        with self.assertRaises(ValueError):
            pve.hosts_content('192.168.50.20 pve.example.home\n', D)

    def test_malformed_blocks(self):
        for content in [pve.BEGIN, pve.END, pve.BEGIN+'\n'+pve.BEGIN]:
            with self.assertRaises(ValueError): pve.hosts_content(content, D)

    def test_reject_private_key(self):
        with self.assertRaises(ValueError): pve.fingerprint('-----BEGIN PRIVATE KEY-----')

    def test_extract_failure_rolls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            anchor = Path(tmp)/'anchor.pem'; hosts = Path(tmp)/'hosts'
            hosts.write_text('127.0.0.1 localhost\n')
            with patch.object(pve, 'ANCHOR', anchor), patch.object(pve, 'HOSTS', hosts), patch.object(pve.os, 'geteuid', return_value=0), patch.object(pve.os, 'chown'), patch.object(pve.subprocess, 'run', side_effect=[subprocess.CalledProcessError(1, 'extract'), None]):
                with self.assertRaises(subprocess.CalledProcessError): pve.apply(D, 'test public certificate')
            self.assertEqual(hosts.read_text(), '127.0.0.1 localhost\n')
            self.assertFalse(anchor.exists())

    def test_bad_policy_rejected_before_trust(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'policy.json'
            for update in [{'hostname':'pve.home\nattack'}, {'address':'8.8.8.8'}, {'ca_file':'../ca.pem'}, {'sha256':'bad'}]:
                data = dict(D, ca_file='ca.pem', sha256='0'*64); data.update(update)
                path.write_text(json.dumps(data)); (path.parent/'ca.pem').write_text('-----BEGIN CERTIFICATE-----\nMAA=\n-----END CERTIFICATE-----\n')
                with self.assertRaises(ValueError): pve.policy(path)

unittest.main()

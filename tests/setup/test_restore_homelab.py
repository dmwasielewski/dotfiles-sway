import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('restore', Path(__file__).resolve().parents[2] / 'scripts/restore-homelab-config.py')
helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.source = Path(self.tmp.name)/'source'; self.source.mkdir()
        self.dest = Path(self.tmp.name)/'dest'
    def test_missing_is_noop(self):
        helper.restore(self.source/'missing', self.dest)
        self.assertFalse(self.dest.exists())
    def test_restore_permissions_idempotence(self):
        (self.source/'tailscale-accept-routes').write_text('true\n')
        (self.source/'nordvpn-homelab.json').write_text('{"subnets":["192.168.50.0/24","100.100.100.100/32"]}')
        helper.restore(self.source, self.dest); helper.restore(self.source, self.dest)
        for name in ['tailscale-accept-routes','nordvpn-homelab.json']:
            self.assertEqual((self.dest/name).read_bytes(), (self.source/name).read_bytes())
            self.assertEqual((self.dest/name).stat().st_mode & 0o777, 0o600)
    def test_conflict_preserved(self):
        (self.source/'tailscale-accept-routes').write_text('true\n')
        self.dest.mkdir(); (self.dest/'tailscale-accept-routes').write_text('false\n')
        with self.assertRaises(ValueError): helper.restore(self.source, self.dest)
        self.assertEqual((self.dest/'tailscale-accept-routes').read_text(), 'false\n')
    def test_invalid_source_no_partial_restore(self):
        (self.source/'tailscale-accept-routes').write_text('invalid')
        (self.source/'nordvpn-homelab.json').write_text('{"subnets":["192.168.50.0/24"]}')
        with self.assertRaises(ValueError): helper.restore(self.source, self.dest)
        self.assertFalse(self.dest.exists())
    def test_reject_symlink(self):
        (self.source/'proxmox-client.json').symlink_to(self.source/'missing')
        with self.assertRaises(ValueError): helper.restore(self.source, self.dest)
    def test_proxmox_pin_failure_no_restore(self):
        (self.source/'proxmox-client.json').write_text('{"hostname":"pve.example.home","address":"192.168.50.10","ca_file":"ca.pem","sha256":"bad"}')
        (self.source/'ca.pem').write_text('unverified')
        with self.assertRaises(ValueError): helper.restore(self.source, self.dest)
        self.assertFalse(self.dest.exists())
    def test_phase_order(self):
        script = (Path(__file__).resolve().parents[2]/'orchestrate.sh').read_text()
        self.assertLess(script.index('restore-homelab-config.py'), script.index('setup-proxmox-client.sh'))
        self.assertLess(script.index('setup-proxmox-client.sh'), script.index('phase_P2()'))

unittest.main()

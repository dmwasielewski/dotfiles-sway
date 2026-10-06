#!/usr/bin/env python3
"""Exception policy tests; all NordVPN calls are mocked."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('policy', Path(__file__).resolve().parents[2] / 'scripts/nordvpn-homelab.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PolicyTests(unittest.TestCase):
    def load(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'policy.json'
            path.write_text(json.dumps(data))
            return policy.load_policy(path)

    def test_rejects_public_broad_tailnet_ipv6_and_host_bits(self):
        for value in ['0.0.0.0/0', '8.8.8.8/32', '100.64.0.0/10', '::/0', '192.168.50.1/24']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.load({'subnets': [value]})
        with self.assertRaises(ValueError):
            self.load({'subnets': []})

    def test_idempotence_preserves_existing_exception(self):
        state = {'172.20.0.0/16'}
        calls = []
        def fake(*args):
            calls.append(args)
            if args == ('settings',):
                return 'Firewall: enabled\nAllowlisted subnets:\n' + ''.join('\t' + n + '\n' for n in sorted(state)) + 'Other: enabled\n'
            action, net = args[1], args[3]
            if action == 'add': state.add(net)
            else: state.remove(net)
            return ''
        nets = self.load({'subnets': ['192.168.50.0/24', '100.80.20.30/32']})
        with patch.object(policy, 'command', fake):
            self.assertEqual(policy.apply(nets), 2)
            self.assertEqual(policy.apply(nets), 0)
        self.assertIn('172.20.0.0/16', state)
        self.assertEqual(sum(c[:2] == ('allowlist', 'add') for c in calls), 2)
        self.assertFalse(any(c[0] in ('connect', 'disconnect', 'set') for c in calls))

    def test_failure_rolls_back_only_new_rules(self):
        state = {'172.20.0.0/16'}
        def fake(*args):
            if args == ('settings',):
                return 'Allowlisted subnets:\n' + ''.join('\t' + n + '\n' for n in state)
            if args[1] == 'add':
                if args[3].startswith('100.'): raise RuntimeError('simulated failure')
                state.add(args[3])
            else: state.remove(args[3])
            return ''
        nets = self.load({'subnets': ['192.168.50.0/24', '100.80.20.30/32']})
        with patch.object(policy, 'command', fake), self.assertRaises(RuntimeError):
            policy.apply(nets)
        self.assertEqual(state, {'172.20.0.0/16'})

    def test_success_exit_without_retained_rule_fails(self):
        nets = self.load({'subnets': ['192.168.50.0/24']})
        with patch.object(policy, 'command', return_value=''), self.assertRaises(RuntimeError):
            policy.apply(nets)

    def test_existing_broader_private_exception_is_not_rewritten(self):
        nets = self.load({'subnets': ['192.168.50.0/24']})
        with patch.object(policy, 'command', return_value='Allowlisted subnets:\n\t192.168.0.0/16\n') as mock:
            self.assertEqual(policy.apply(nets), 0)
            self.assertTrue(all(call.args == ('settings',) for call in mock.call_args_list))


if __name__ == '__main__':
    unittest.main()

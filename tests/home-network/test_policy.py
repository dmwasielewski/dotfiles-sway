import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('home', Path(__file__).resolve().parents[2] / 'scripts/home-network.py')
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)

class PolicyTests(unittest.TestCase):
    def test_new_uuid_same_wifi(self):
        policy = {'wifi': [{'ssid': 'Example', 'security': 'sae'}], 'ethernet_uuids': []}
        self.assertEqual(home.location(policy, [{'uuid': 'new', 'type': 'wifi', 'ssid': 'Example', 'security': 'sae'}]), 'home')
        self.assertEqual(home.location(policy, [{'type': 'wifi', 'ssid': 'Example', 'security': 'none'}]), 'away')
    def test_bridge_and_offline_do_not_leave_home(self):
        self.assertEqual(home.location({'wifi': [], 'ethernet_uuids': []}, [{'type': 'bridge'}]), 'offline')
    def test_any_home_link_wins(self):
        p = {'wifi': [{'ssid': 'Home', 'security': 'sae'}], 'ethernet_uuids': []}
        self.assertEqual(home.location(p, [{'type':'ethernet','uuid':'other'}, {'type':'wifi','ssid':'Home','security':'sae'}]), 'home')
    def test_manual_override_survives_monitor_and_restart(self):
        state, actions = home.plan({}, 'home', {'adguard': True, 'nordvpn': False, 'tailscale': True}, 'boot')
        self.assertEqual(actions, [('adguard', False), ('tailscale', False)])
        self.assertEqual(home.plan(state, 'home', {}, 'boot'), (state, []))
        self.assertEqual(home.plan(state, 'offline', {}, 'boot'), (state, []))
        outside, actions = home.plan(state, 'away', {}, 'boot')
        self.assertEqual(actions, [('adguard', True), ('tailscale', True)])
        self.assertEqual(outside['mode'], 'away')
    def test_reboot_home_preserves_original_snapshot(self):
        s = {'mode':'home','boot':'old','restore':{'adguard':True,'nordvpn':False,'tailscale':False}}
        new, actions = home.plan(s, 'home', {'adguard':False,'nordvpn':True,'tailscale':False}, 'new')
        self.assertEqual(new['restore'], s['restore'])
        self.assertEqual(actions, [('nordvpn',False)])
    def test_initial_away_never_enables_apps(self):
        s, actions = home.plan({}, 'away', {}, 'boot')
        self.assertEqual(actions, [])
    def test_invalid_policy_rejected(self):
        for value in ({'wifi':[],'ethernet_uuids':[]}, {'wifi':[{'ssid':'X','security':'none'}]}, {'wifi':'X'}):
            with self.assertRaises(ValueError): home.validate_policy(value)
    def test_failed_transition_rolls_back(self):
        calls=[]
        def change(app, enabled):
            calls.append((app, enabled))
            if app=='tailscale' and not enabled: raise RuntimeError('failure')
        with self.assertRaises(RuntimeError):
            home.apply_actions([('adguard',False),('tailscale',False)], {'adguard':True,'tailscale':True}, change)
        self.assertIn(('adguard',True), calls)

class RuntimeTests(unittest.TestCase):
    def test_persisted_transitions_and_manual_enable(self):
        with tempfile.TemporaryDirectory() as temp:
            config, state = Path(temp)/'policy.json', Path(temp)/'state.json'
            config.write_text('{"wifi":[{"ssid":"Home","security":"sae"}]}')
            current = dict.fromkeys(home.APPS, True)
            active = [{'type':'wifi','ssid':'Home','security':'sae'}]
            calls=[]
            def set_app(app, enabled):
                calls.append((app,enabled)); current[app]=enabled
            with patch.object(home,'CONFIG',config), patch.object(home,'STATE',state), \
                 patch.object(home,'links',side_effect=lambda:active), \
                 patch.object(home,'snapshot',side_effect=lambda:current.copy()), \
                 patch.object(home,'change',side_effect=set_app), \
                 patch('sys.argv',['home-network.py','once']):
                home.main()
                self.assertEqual(current, dict.fromkeys(home.APPS,False))
                current['tailscale']=True
                calls.clear(); home.main()
                self.assertEqual(calls, [])
                active.clear(); home.main()
                self.assertEqual(calls, [])
                active.append({'type':'ethernet','uuid':'outside'})
                home.main()
                self.assertEqual(current, dict.fromkeys(home.APPS,True))
                calls.clear(); home.main()
                self.assertEqual(calls, [])

if __name__=='__main__': unittest.main()

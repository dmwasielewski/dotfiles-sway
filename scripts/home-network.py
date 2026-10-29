#!/usr/bin/env python3
"""Opt-in home network transitions; no credentials or vendor settings modified."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

APPS = ('adguard', 'nordvpn', 'tailscale')
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'dotfiles/home-network.json'
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'dotfiles/home-network.json'


def run(args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=45,
                            env={**os.environ, 'LC_ALL':'C', 'NO_COLOR':'1'})
    if result.returncode:
        raise RuntimeError('Command failed: ' + Path(args[0]).name + ' ' + args[1])
    return result.stdout.strip()


def validate_policy(p):
    if not isinstance(p, dict) or set(p) - {'wifi','ethernet_uuids'}:
        raise ValueError('Invalid home policy')
    wifi, wired = p.get('wifi', []), p.get('ethernet_uuids', [])
    if not isinstance(wifi, list) or not isinstance(wired, list) or not (wifi or wired):
        raise ValueError('At least one explicit home network required')
    for item in wifi:
        if (not isinstance(item, dict) or set(item) != {'ssid','security'} or
                not isinstance(item['ssid'], str) or not item['ssid'] or
                item['security'] not in ('sae','wpa-psk','wpa-eap','wpa-eap-suite-b-192')):
            raise ValueError('Explicit secured Wi-Fi required')
    for item in wired:
        if not isinstance(item, str): raise ValueError("Ethernet UUID must be a string")
        uuid.UUID(item)
    return {'wifi':wifi, 'ethernet_uuids':wired}


def links():
    active = []
    for row in run(['nmcli','-t','-f','UUID,TYPE','connection','show','--active']).splitlines():
        ident, kind = row.split(':', 1)
        if kind not in ('802-11-wireless','802-3-ethernet'):
            continue
        if run(['nmcli','-g','GENERAL.STATE','connection','show',ident]) != 'activated':
            continue
        item = {'uuid':ident, 'type':'wifi' if kind=='802-11-wireless' else 'ethernet'}
        if item['type']=='wifi':
            item['ssid'] = run(['nmcli','-g','802-11-wireless.ssid','connection','show',ident])
            item['security'] = run(['nmcli','-g','802-11-wireless-security.key-mgmt','connection','show',ident])
        active.append(item)
    return active


def location(policy, active):
    physical = [x for x in active if x['type'] in ('wifi','ethernet')]
    for item in physical:
        if item['type']=='wifi' and {'ssid':item['ssid'], 'security':item['security']} in policy['wifi']:
            return 'home'
        if item['type']=='ethernet' and item['uuid'] in policy['ethernet_uuids']:
            return 'home'
    return 'away' if physical else 'offline'


def snapshot():
    states = {}
    for app in APPS:
        binary = 'adguard-cli' if app=='adguard' else app
        if not shutil.which(binary):
            states[app] = None
            continue
        if app=='tailscale':
            value = json.loads(run([binary,'status','--json']))['BackendState']
            if value not in ('Running','Stopped'):
                raise RuntimeError('Tailscale not ready; transition cancelled')
            states[app] = value=='Running'
        else:
            text = run([binary,'status'])
            if app=='nordvpn':
                if 'Status: Disconnected' in text: states[app] = False
                elif 'Status: Connected' in text: states[app] = True
                else: raise RuntimeError('NordVPN state unknown; transition cancelled')
            else:
                if 'is not running' in text: states[app] = False
                elif 'proxy server is running' in text or 'Protection is enabled' in text: states[app] = True
                else: raise RuntimeError('AdGuard state unknown; transition cancelled')
    return states


def change(app, enabled):
    commands = {'adguard':['adguard-cli','start' if enabled else 'stop'],
                'nordvpn':['nordvpn','connect' if enabled else 'disconnect'],
                'tailscale':['tailscale','up' if enabled else 'down']}
    run(commands[app])


def plan(state, target, current, boot):
    if target=='offline' or (state.get('mode')==target and state.get('boot')==boot):
        return state, []
    if target=='home':
        restore = state.get('restore', {}) if state.get('mode')=='home' else current.copy()
        new = {'mode':'home','boot':boot,'restore':restore}
        return new, [(app,False) for app in APPS if current.get(app) is True]
    actions = [(app,True) for app in APPS if state.get('restore',{}).get(app) is True] if state.get('mode')=='home' else []
    return {'mode':'away','boot':boot,'restore':{}}, actions


def apply_actions(actions, before, setter=None):
    setter = setter or change
    attempted = []
    try:
        for app, enabled in actions:
            attempted.append(app)
            setter(app, enabled)
    except Exception as original:
        failures = []
        for app in reversed(attempted):
            if before.get(app) is not None:
                try: setter(app, before[app])
                except Exception: failures.append(app)
        if failures:
            raise RuntimeError('Rollback incomplete: ' + ', '.join(failures)) from original
        raise


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_suffix('.tmp')
    fd = os.open(temp, os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as out:
        json.dump(data, out)
        out.flush()
        os.fsync(out.fileno())
    os.replace(temp, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check','status','is-home','once','watch','enroll-wifi'])
    args = parser.parse_args()
    if args.action=='enroll-wifi':
        candidates = [x for x in links() if x['type']=='wifi']
        if len(candidates)!=1: raise ValueError('Connect to exactly one home Wi-Fi first')
        policy = json.loads(CONFIG.read_text()) if CONFIG.exists() else {'wifi':[], 'ethernet_uuids':[]}
        entry = {k:candidates[0][k] for k in ('ssid','security')}
        if entry not in policy['wifi']: policy['wifi'].append(entry)
        save(CONFIG, validate_policy(policy))
        print('Home Wi-Fi enrolled; no Wi-Fi password stored')
        return
    policy = validate_policy(json.loads(CONFIG.read_text()))
    if args.action=='check':
        print('Home network policy valid')
        return
    if args.action=='is-home':
        if location(policy,links())!='home': raise SystemExit(1)
        return
    if args.action=='status':
        print(json.dumps({'location':location(policy,links()), 'apps':snapshot(),
                          'transition':json.loads(STATE.read_text()) if STATE.exists() else {}}, indent=2))
        return
    STATE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(STATE.with_suffix('.lock'), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
        state = json.loads(STATE.read_text()) if STATE.exists() else {}
        # A killed transition may have partially changed apps. Restore its snapshot,
        # then stop for inspection instead of silently declaring success.
        if 'pending' in state:
            for app, enabled in state['pending'].items():
                if enabled is not None: change(app, enabled)
            del state['pending']
            save(STATE, state)
            raise RuntimeError('Interrupted transition recovered; restart after inspection')
        boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        previous, count = None, 0
        while True:
            try:
                target = location(policy, links())
            except (OSError, RuntimeError, subprocess.SubprocessError):
                if args.action=='once': raise
                previous, count = None, 0
                print('NetworkManager temporarily unavailable; no application changes', flush=True)
                time.sleep(5)
                continue
            count = count+1 if previous==target else 1
            previous = target
            if count>=3 or args.action=='once':
                if target!='offline' and (state.get('mode')!=target or state.get('boot')!=boot):
                    before = snapshot()
                    new, actions = plan(state, target, before, boot)
                    save(STATE, {**state, 'pending':before})
                    try:
                        apply_actions(actions, before)
                        actual = snapshot()
                        if any(actual[app] is not enabled for app,enabled in actions):
                            apply_actions([(app,before[app]) for app,_ in actions], actual)
                            raise RuntimeError('Application did not reach requested state')
                    except Exception:
                        # Keep recovery marker: a later explicit restart restores
                        # the original snapshot, including partial command failures.
                        raise
                    state = new
                    save(STATE, state)
                    print('Home network transition completed: '+target, flush=True)
            if args.action=='once': return
            time.sleep(5)


if __name__=='__main__':
    try: main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as exc:
        raise SystemExit('Home network automation stopped: '+str(exc))

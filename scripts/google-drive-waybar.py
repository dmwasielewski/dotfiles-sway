#!/usr/bin/python3
"""Google Drive availability and connection UI; never print account secrets."""
import configparser
import fcntl
import html
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HOME = Path.home()
CONFIG = HOME / '.config/google-drive/rclone.conf'
BINARY = HOME / '.local/opt/rclone/current/rclone'
MOUNT = HOME / 'GoogleDrive'
SERVICE = 'google-drive.service'


def configured():
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(CONFIG)
        return (parser.get('gdrive', 'type', fallback='') == 'drive'
                and bool(parser.get('gdrive', 'token', fallback='').strip()))
    except (OSError, configparser.Error):
        return False


def mounted():
    for row in Path('/proc/self/mountinfo').read_text().splitlines():
        left, right = row.split(' - ', 1)
        location = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), left.split()[4])
        if (location == os.path.realpath(MOUNT) and right.split()[0] == 'fuse.rclone'
                and right.split()[1] == 'gdrive:'):
            return True
    return False


def probe():
    try:
        result = subprocess.run(
            [str(BINARY), 'about', 'gdrive:', '--config', str(CONFIG), '--json',
             '--contimeout=3s', '--timeout=3s', '--retries=1', '--low-level-retries=1',
             '--log-level=ERROR'], capture_output=True, text=True, timeout=6)
        if result.returncode == 0:
            quota = json.loads(result.stdout)
            if isinstance(quota, dict) and any(k in quota for k in ('total', 'used', 'free')):
                return 'connected', 'Connected to your Google Drive account'
            return 'warning', 'Cannot confirm Google Drive account access'
        # Inspect locally, but never expose raw stderr (may contain account data).
        if re.search(r'timeout|timed out|no such host|network is unreachable|connection refused|connection reset|temporary failure', result.stderr, re.I):
            return 'offline', 'Google Drive is unreachable (network, DNS or service)'
        return 'warning', 'Check Google Drive login, permissions or service limits'
    except subprocess.TimeoutExpired:
        return 'offline', 'Google Drive did not respond within 6 seconds'
    except (OSError, ValueError):
        return 'warning', 'Cannot check Google Drive account access'


def status():
    if not configured():
        return 'disconnected', 'Google Drive account is not connected; click to configure'
    if not mounted():
        return 'disconnected', '~/GoogleDrive is not mounted; click to start'
    return probe()


def notify(message):
    subprocess.run(['notify-send', 'Google Drive', message], check=False)


def check_mount():
    if not configured():
        raise RuntimeError('Connect your Google Drive account first')
    MOUNT.mkdir(exist_ok=True)
    # Never hide existing local files or reuse another filesystem's mount.
    if os.path.ismount(MOUNT) or any(MOUNT.iterdir()):
        raise RuntimeError('~/GoogleDrive must be an empty, unmounted directory')


def start_and_open():
    if not mounted():
        check_mount()
        subprocess.run(['systemctl', '--user', 'enable', '--now', SERVICE],
                       check=True, capture_output=True, timeout=50)
    if not mounted():
        raise RuntimeError('Google Drive did not mount; open the service log from the menu')
    subprocess.Popen(['thunar', str(MOUNT)], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def configure():
    os.umask(0o077)
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.parent.chmod(0o700)
    with (CONFIG.parent / 'connection.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            notify('An account setup window is already open.')
            return
        if mounted() or subprocess.run(['systemctl', '--user', 'is-active', '--quiet', SERVICE]).returncode == 0:
            print('Drive is active. Keep its account/config unchanged while uploads may be pending.')
            input('Press Enter to close...')
            return
        print('Google Drive files on demand\n')
        print('Create a remote named gdrive. Storage: drive (Google Drive). Scope: drive.')
        print('Authorize YOUR Google account in the browser. Do not share its tokens.')
        print('Rclone recommends your own Google OAuth client ID and client secret:')
        print('https://rclone.org/drive/#making-your-own-client-id')
        print('The shared client is being retired in 2026; account login may require your own client.')
        print('Use an unencrypted config here; this private file is required for unattended mounting.\n')
        try:
            command = [str(BINARY), 'config', '--config', str(CONFIG)]
            if configured():
                print('Reconnect the SAME Google account; do not change accounts with pending cached writes.')
                command += ['reconnect', 'gdrive:']
            subprocess.run(command, check=True)
        finally:
            if CONFIG.exists():
                CONFIG.chmod(0o600)
        if configured():
            start_and_open()
            print('\nConnected. The mount starts automatically with your graphical session.')
        else:
            print('\nAccount setup is incomplete. Open this window again to continue.')
        input('Press Enter to close...')


def open_drive():
    if not configured():
        subprocess.Popen(['foot', '-a', 'google-drive-setup', '-T', 'Google Drive setup',
                          str(HOME / '.local/bin/google-drive-waybar'), 'configure'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    else:
        start_and_open()


def menu():
    options = ['Open files', 'Connect account', 'Open in browser', 'Show service log']
    selected = subprocess.run(['rofi', '-dmenu', '-p', 'Google Drive'],
                              input='\n'.join(options), text=True, capture_output=True)
    if selected.returncode != 0:
        return
    action = selected.stdout.strip()
    if action == options[0]:
        open_drive()
    elif action == options[1]:
        subprocess.Popen(['foot', '-a', 'google-drive-setup', '-T', 'Google Drive setup',
                          str(HOME / '.local/bin/google-drive-waybar'), 'configure'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    elif action == options[2]:
        subprocess.Popen(['xdg-open', 'https://drive.google.com'], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif action == options[3]:
        subprocess.Popen(['foot', '-T', 'Google Drive log', 'journalctl', '--user',
                          '-u', SERVICE, '-n', '40', '-f'], start_new_session=True)


def main():
    if len(sys.argv) > 1:
        action = sys.argv[1]
        try:
            if action == 'open': open_drive()
            elif action == 'configure': configure()
            elif action == 'menu': menu()
            elif action == 'check-mount': check_mount()
            else: raise RuntimeError('Unknown Google Drive action')
        except Exception:
            if action == 'check-mount':
                print('Google Drive cannot start: check account setup and empty mount folder.', file=sys.stderr)
            else:
                notify('Cannot open Google Drive. Check account setup, the empty mount folder and service log.')
            return 1
        return 0
    try:
        state, message = status()
    except Exception:
        state, message = 'warning', 'Cannot check Google Drive status'
    tooltip = ('Google Drive\n' + message + '\n~/GoogleDrive • checked every 30 seconds\n'
               'Click: open files or connect account • Right-click: menu\n'
               'Account availability, not confirmation of completed uploads.')
    print(json.dumps({'text': '\uf3aa', 'class': state, 'tooltip': html.escape(tooltip)}, ensure_ascii=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/python3
"""No failed access probe may claim a working cloud connection."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('gdrive', Path(__file__).resolve().parents[1] / 'scripts/google-drive-waybar.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GoogleDrive(unittest.TestCase):
    def test_not_configured_never_contacts_google(self):
        with patch.object(module, 'configured', return_value=False), patch.object(module, 'probe') as probe:
            self.assertEqual(module.status()[0], 'disconnected')
            probe.assert_not_called()

    def test_unmounted_never_claims_connected(self):
        with patch.object(module, 'configured', return_value=True), patch.object(module, 'mounted', return_value=False), patch.object(module, 'probe') as probe:
            self.assertEqual(module.status()[0], 'disconnected')
            probe.assert_not_called()

    def test_quota_check(self):
        with patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '{"free": 0}', '')):
            self.assertEqual(module.probe()[0], 'connected')

    def test_bad_json_is_not_success(self):
        for text in ['not-json', '{}', '[]']:
            with self.subTest(text=text), patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, text, '')):
                self.assertEqual(module.probe()[0], 'warning')

    def test_network_failure_sanitizes_details(self):
        with patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'dial tcp: timeout fake-secret')):
            state, message = module.probe()
            self.assertEqual(state, 'offline')
            self.assertNotIn('fake-secret', message)

    def test_auth_failure_sanitizes_details(self):
        with patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'invalid_grant fake-secret')):
            state, message = module.probe()
            self.assertEqual(state, 'warning')
            self.assertNotIn('fake-secret', message)

    def test_deadline(self):
        with patch.object(module.subprocess, 'run', side_effect=subprocess.TimeoutExpired('rclone', 6)):
            self.assertEqual(module.probe()[0], 'offline')

    def test_configuration_requires_google_drive_and_token(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'rclone.conf'
            with patch.object(module, 'CONFIG', config):
                self.assertFalse(module.configured())
                for text, expected in [('[gdrive]\ntype = drive\ntoken = fake-token\n', True),
                                       ('[gdrive]\ntype = onedrive\ntoken = fake-token\n', False),
                                       ('[gdrive]\ntype = drive\n', False)]:
                    config.write_text(text)
                    self.assertEqual(module.configured(), expected)

    def test_mount_must_belong_to_our_remote(self):
        line = '123 1 0:9 / /tmp/gdrive rw - fuse.rclone {source} rw\n'
        with patch.object(module, 'MOUNT', Path('/tmp/gdrive')):
            for source, expected in [('gdrive:', True), ('other:', False)]:
                with self.subTest(source=source), patch.object(module.Path, 'read_text', return_value=line.format(source=source)):
                    self.assertEqual(module.mounted(), expected)

    def test_existing_local_files_cannot_be_hidden(self):
        with tempfile.TemporaryDirectory() as directory:
            mount = Path(directory) / 'GoogleDrive'
            mount.mkdir()
            (mount / 'local-file').write_text('keep')
            with patch.object(module, 'MOUNT', mount), patch.object(module, 'configured', return_value=True):
                with self.assertRaises(RuntimeError):
                    module.check_mount()
            self.assertEqual((mount / 'local-file').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()

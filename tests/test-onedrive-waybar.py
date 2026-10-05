#!/usr/bin/python3
"""Failure cases must never report successful cloud access."""
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location('indicator', Path(__file__).resolve().parents[1] / 'scripts/onedrive-waybar.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Availability(unittest.TestCase):
    def test_unmounted_does_not_contact_cloud(self):
        with patch.object(module, 'mounted', return_value=False), patch.object(module, 'probe') as probe:
            self.assertEqual(module.status(Path('/tmp/no-account'))[0], 'disconnected')
            probe.assert_not_called()

    def test_authenticated_metadata(self):
        with patch.object(module.urllib.request, 'urlopen') as request:
            request.return_value.__enter__.return_value = io.BytesIO(b'{"id":"root"}')
            self.assertEqual(module.probe('fake')[0], 'connected')

    def test_network_failure(self):
        with patch.object(module.urllib.request, 'urlopen', side_effect=urllib.error.URLError('offline')):
            self.assertEqual(module.probe('fake')[0], 'offline')

    def test_auth_and_service_failures(self):
        for code in (401,403,429,503):
            with self.subTest(code=code), patch.object(module.urllib.request, 'urlopen', side_effect=urllib.error.HTTPError('https://example.invalid',code,'error',{},None)):
                self.assertEqual(module.probe('fake')[0], 'warning')

    def test_invalid_response(self):
        with patch.object(module.urllib.request, 'urlopen') as request:
            request.return_value.__enter__.return_value = io.BytesIO(b'{}')
            self.assertEqual(module.probe('fake')[0], 'warning')

if __name__ == '__main__':
    unittest.main()

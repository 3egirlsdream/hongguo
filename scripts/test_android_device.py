import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import android_device
import sync_source


class AndroidDeviceTests(unittest.TestCase):
    def test_login_reuses_installed_application_without_install_or_uninstall(self):
        response = subprocess.CompletedProcess([], 0,
            'INSTRUMENTATION_RESULT: summary={"loggedIn":true,"reused_session":true}\n', '')
        with patch.object(android_device, 'adb_path', return_value='/sdk/adb'), patch.object(
            android_device.subprocess, 'run', return_value=response
        ) as run:
            self.assertEqual(android_device.run_probe('login'), {'loggedIn': True, 'reused_session': True})
            command = run.call_args.args[0]
            self.assertEqual(command[:2], ['/sdk/adb', 'shell'])
            self.assertNotIn('uninstall', command[2])
            self.assertNotIn(' install ', command[2])

    def test_native_failure_does_not_expose_otp_or_sms_content(self):
        response = subprocess.CompletedProcess([], 0,
            'INSTRUMENTATION_RESULT: error=验证码 123456\n', '')
        with patch.object(android_device, 'adb_path', return_value='/sdk/adb'), patch.object(
            android_device.subprocess, 'run', return_value=response
        ):
            with self.assertRaises(RuntimeError) as caught:
                android_device.run_probe('login')
            self.assertNotIn('123456', str(caught.exception))

    def test_personal_config_is_private_and_excluded_from_source(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / '.local' / 'android-device.json'
            with patch.object(android_device, 'CONFIG', config), patch('sys.argv', [
                'android_device.py', 'configure', '--phone', '18000000000', '--subscription', '1'
            ]), contextlib.redirect_stdout(io.StringIO()):
                android_device.main()
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(config.read_text())['subscription'], 1)
            self.assertTrue(sync_source.excluded(Path('.local/android-device.json')))
            self.assertTrue(sync_source.excluded(Path('scripts/.local/android-device.json')))


if __name__ == '__main__':
    unittest.main()

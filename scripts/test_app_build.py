import os
from pathlib import Path
import runpy
import sys
import unittest
from unittest import mock

from app_build import BuildVariant


class AppBuildTests(unittest.TestCase):
    def test_build_scripts_use_one_core_flutter_and_package_configuration(self):
        root = Path(__file__).resolve().parent
        for target in ['android']:
            script = root / f'build_{target}.py'
            with self.subTest(target=target), mock.patch.object(sys, 'argv', [str(script)]), \
                    mock.patch.dict(os.environ, {'PATH': '/tools'}, clear=True), \
                    mock.patch('shutil.which', return_value='/tools/flutter'), \
                    mock.patch('subprocess.run') as run:
                runpy.run_path(str(script), run_name='__main__')
            calls = [call.args[0] for call in run.call_args_list]
            self.assertTrue(any(any(str(arg).endswith('build_native.py') for arg in call) for call in calls))
            self.assertTrue(any('build' in call for call in calls))
            self.assertTrue(any(any(str(arg).endswith('package_release.py') for arg in call) for call in calls))
            self.assertEqual(BuildVariant().slug, 'yeguo')


if __name__ == '__main__':
    unittest.main()

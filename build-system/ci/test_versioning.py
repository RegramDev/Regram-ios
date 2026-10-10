"""Offline regressions for stable build identities and workflow environment output."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import versioning


class VersioningChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.versions = self.root / 'versions.json'

    def write(self, value):
        self.versions.write_text(json.dumps({'app': '13.0', 'build': value}))

    def test_declared_build_and_manual_increment(self):
        self.write(34588)
        self.assertEqual(versioning.build_number(self.versions), '34588')
        self.write(34589)
        self.assertEqual(versioning.build_number(self.versions), '34589')

    def test_invalid_and_missing_values_fail(self):
        for value in [None, True, False, '34588', 34588.5, 0, -1, 2147483648]:
            with self.subTest(value=value):
                self.write(value)
                with self.assertRaises(ValueError):
                    versioning.build_number(self.versions)
        self.versions.write_text('{"app":"13.0"}')
        with self.assertRaises(ValueError):
            versioning.build_number(self.versions)

    def test_stale_workflow_override_is_rejected(self):
        self.write(34588)
        self.assertEqual(versioning.build_number(self.versions, expected='34588'), '34588')
        for value in ['40007', '34589', '', '034588', '34588\n']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                versioning.build_number(self.versions, expected=value)

    def test_cli_is_independent_of_run_counters_and_exports_declared_value(self):
        for run, attempt in [('7', '1'), ('9999', '2')]:
            environment = self.root / f'env-{run}'
            env = dict(os.environ, GITHUB_RUN_NUMBER=run, GITHUB_RUN_ATTEMPT=attempt)
            env.pop('REGRAM_BUILD_NUMBER', None)
            output = subprocess.check_output(['python3', str(Path(versioning.__file__)), '--github-env', str(environment)], env=env, text=True)
            self.assertEqual(output.strip(), versioning.build_number())
            self.assertEqual(environment.read_text(), f'REGRAM_BUILD_NUMBER={versioning.build_number()}\n')

    def test_ci_script_rejects_override_before_tools_or_credentials(self):
        env = dict(os.environ, REGRAM_BUILD_NUMBER='40007')
        script = Path(versioning.__file__).with_name('build.sh')
        result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('REGRAM_BUILD_NUMBER must match', result.stderr)
        self.assertNotIn('xcode', result.stdout)


if __name__ == '__main__':
    unittest.main()

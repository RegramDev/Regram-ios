"""Exercise beta identity guards and the compiled App Group selection without account data."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from prepare import VARIABLES, validate_configuration

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'build-system/Make'))
from BuildConfiguration import BuildConfiguration, DirectoryCodesigningSource, GitCodesigningSource


class BetaIdentityTests(unittest.TestCase):
    def configuration(self, bundle, appstore):
        config = {key: (False if kind is bool else '') for key, kind in VARIABLES.items()}
        config.update(telegram_bundle_id=bundle, telegram_is_appstore_build=appstore,
                      telegram_team_id='FIXTURE001', telegram_api_id='1',
                      telegram_api_hash='0' * 32, telegram_aps_environment='production')
        return config

    def make_configuration(self, bundle, appstore):
        return BuildConfiguration(
            rg_config='{}', bundle_id=bundle, api_id='1', api_hash='0' * 32,
            team_id='FIXTURE001', app_center_id='', is_internal_build='false',
            is_appstore_build=appstore, appstore_id='', app_specific_url_scheme='',
            premium_iap_product_id='', enable_siri=False, enable_icloud=False)

    def bazel_guard(self):
        def fail(message):
            raise ValueError(message)
        scope = {'fail': fail}
        path = ROOT / 'build-system/bazel-utils/beta_identity.bzl'
        # This Starlark guard uses the Python-compatible subset; execute the production function.
        exec(compile(path.read_text(), str(path), 'exec'), scope)
        return scope['require_beta_bundle_id']

    def test_all_configuration_entry_points_agree(self):
        guard = self.bazel_guard()
        for bundle, appstore, accepted in [
            ('dev.regram.ios', 'false', True),
            ('com.regram.app', 'false', False),
            ('com.regram.app', 'true', False),
            ('dev.regram.ios', 'true', True),
            ('com.example.other', 'true', False),
            ('com.example.other', 'false', False),
        ]:
            with self.subTest(bundle=bundle, appstore=appstore):
                calls = [lambda: validate_configuration(self.configuration(bundle, appstore)),
                         lambda: self.make_configuration(bundle, appstore),
                         lambda: guard(bundle)]
                for call in calls:
                    if accepted:
                        call()
                    else:
                        with self.assertRaises(ValueError):
                            call()

    def test_signing_sources_accept_only_the_beta_identity(self):
        for bundle in ['com.regram.app', 'dev.regram.ios', 'com.example.other']:
            calls = [lambda: DirectoryCodesigningSource('/unused', 'FIXTURE001', bundle),
                     lambda: GitCodesigningSource('unused', None, 'FIXTURE001', bundle,
                                                  'appstore', None, False)]
            with self.subTest(bundle=bundle):
                for call in calls:
                    if bundle != 'dev.regram.ios':
                        with self.assertRaises(ValueError):
                            call()
                    else:
                        self.assertEqual(call().bundle_id, bundle)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'requires Swift on macOS')
    def test_compiled_app_and_extension_helpers_use_the_selected_group(self):
        source = ROOT / 'Regram/RGAppGroupIdentifier/Sources/RGAppGroupIdentifier.swift'
        with tempfile.TemporaryDirectory(prefix='regram-beta-identity-') as temporary:
            work = Path(temporary)
            main = work / 'main.swift'
            main.write_text('''import Foundation
let expected = CommandLine.arguments[1]
precondition(rgBaseBundleIdentifier() == expected)
precondition(rgOwnAppGroupIdentifier() == "group." + expected)
precondition(!rgIsSandboxOnlyBuild)
''')
            for bundle in ['dev.regram.ios']:
                with self.subTest(bundle=bundle):
                    binary = work / bundle
                    result = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                                             '-warnings-as-errors', str(source),
                                             str(main), '-o', str(binary)],
                                            capture_output=True, text=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    subprocess.run([str(binary), bundle], check=True, timeout=10)


if __name__ == '__main__':
    unittest.main()

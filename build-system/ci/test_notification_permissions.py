"""Check generated CMS metadata and final-package notification capability boundaries."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

import package
import prepare

KEY = 'com.apple.developer.usernotifications.filtering'


class NotificationPermissionChecks(unittest.TestCase):
    def test_seven_profiles_request_filtering_only_for_service(self):
        config = {name: (False if kind is bool else '') for name, kind in prepare.VARIABLES.items()}
        config.update(telegram_bundle_id='dev.regram.ios', telegram_api_id='1',
                      telegram_api_hash='0' * 32, telegram_team_id='TESTTEAM01',
                      telegram_aps_environment='production')
        with tempfile.TemporaryDirectory(prefix='regram-capability-check-') as directory:
            root = Path(directory)
            prepare.prepare(config, root / 'configuration', root / 'bazel')
            for name, suffix in prepare.PROFILE_SUFFIXES.items():
                path = root / 'configuration/provisioning' / (name + '.mobileprovision')
                result = subprocess.run(['openssl', 'cms', '-verify', '-binary', '-inform', 'DER', '-noverify', '-nosigs', '-in', str(path)], capture_output=True, check=True)
                rights = plistlib.loads(result.stdout)['Entitlements']
                self.assertEqual(rights.get(KEY) is True, name == 'NotificationService')
                self.assertEqual(rights['application-identifier'], 'TESTTEAM01.dev.regram.ios' + suffix)
                self.assertEqual(rights['com.apple.security.application-groups'], ['group.dev.regram.ios'])

    def test_package_rejects_missing_or_misplaced_filtering(self):
        with tempfile.TemporaryDirectory(prefix='regram-filtering-boundary-') as directory:
            root = Path(directory)
            for service in [False, True]:
                (root / 'Info.plist').write_bytes(plistlib.dumps({'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.usernotifications.service' if service else 'com.apple.usernotifications.content-extension'}}))
                for value in [None, False, True, 'true']:
                    rights = {} if value is None else {KEY: value}
                    if service == (value is True):
                        package.verify_notification_filtering(root, rights)
                    else:
                        with self.assertRaises(RuntimeError):
                            package.verify_notification_filtering(root, rights)


if __name__ == '__main__':
    unittest.main()

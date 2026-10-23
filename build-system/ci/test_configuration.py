"""Current RG build configuration is accepted; Swiftgram aliases are rejected."""
import unittest

from prepare import VARIABLES, validate_configuration
from package import verify_share_access_entitlements


class ConfigurationChecks(unittest.TestCase):
    def configuration(self):
        result = {name: (False if kind is bool else '') for name, kind in VARIABLES.items()}
        result.update(rg_config='{"fixture": true}', telegram_bundle_id='com.regram.app',
                      telegram_api_id='1', telegram_api_hash='0' * 32,
                      telegram_team_id='TESTTEAM01', telegram_aps_environment='production')
        return result

    def test_current_configuration_preserves_values(self):
        config = self.configuration()
        self.assertEqual(validate_configuration(config), config)

    def test_swiftgram_configuration_is_not_migrated(self):
        config = self.configuration()
        config['sg_config'] = config.pop('rg_config')
        with self.assertRaises(ValueError):
            validate_configuration(config)

    def test_swiftgram_configuration_is_not_an_extra_alias(self):
        config = self.configuration()
        config['sg_config'] = config['rg_config']
        with self.assertRaises(ValueError):
            validate_configuration(config)


class ShareAccessEntitlementChecks(unittest.TestCase):
    def entitlements(self):
        return {
            'com.apple.security.application-groups': ['group.com.regram.fixture'],
            'com.apple.developer.team-identifier': 'TESTTEAM01',
            'keychain-access-groups': ['TESTTEAM01.com.regram.fixture'],
        }

    def test_profile_shared_access_is_accepted(self):
        verify_share_access_entitlements('com.regram.fixture.Share', self.entitlements())

    def test_app_group_only_share_override_is_rejected(self):
        # Telegram 13.1.1's explicit Share entitlements omit the profile's keychain and team.
        with self.assertRaisesRegex(RuntimeError, 'team and keychain'):
            verify_share_access_entitlements('com.regram.fixture.Share', {
                'com.apple.security.application-groups': ['group.com.regram.fixture'],
                'application-identifier': 'TESTTEAM01.com.regram.fixture.Share',
                'get-task-allow': False,
            })

    def test_missing_or_invalid_profile_access_is_rejected(self):
        for key, values in {
            'com.apple.developer.team-identifier': [None, ''],
            'keychain-access-groups': [None, [], [''], 'TESTTEAM01.com.regram.fixture'],
        }.items():
            for value in values:
                with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                    verify_share_access_entitlements('com.regram.fixture.Share', self.entitlements() | {key: value})

    def test_other_extensions_keep_their_existing_entitlement_contract(self):
        verify_share_access_entitlements('com.regram.fixture.Widget', {
            'com.apple.security.application-groups': ['group.com.regram.fixture'],
        })


if __name__ == '__main__':
    unittest.main()

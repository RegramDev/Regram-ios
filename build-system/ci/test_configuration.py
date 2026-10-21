"""Current RG build configuration is accepted; Swiftgram aliases are rejected."""
import unittest

from prepare import VARIABLES, validate_configuration


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


if __name__ == '__main__':
    unittest.main()

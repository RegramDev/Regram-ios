#!/usr/bin/env python3
"""Prepare ignored CI build inputs and synthetic provisioning metadata for reference IPAs."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import uuid

VARIABLES = {
    'sg_config': str,
    'telegram_api_hash': str,
    'telegram_api_id': str,
    'telegram_app_center_id': str,
    'telegram_app_specific_url_scheme': str,
    'telegram_appstore_id': str,
    'telegram_aps_environment': str,
    'telegram_bundle_id': str,
    'telegram_enable_icloud': bool,
    'telegram_enable_siri': bool,
    'telegram_enable_watch': bool,
    'telegram_is_appstore_build': str,
    'telegram_is_internal_build': str,
    'telegram_premium_iap_product_id': str,
    'telegram_team_id': str,
    'telegram_use_xcode_managed_codesigning': bool,
}
PROFILE_SUFFIXES = {
    'Telegram': '',
    'Share': '.Share',
    'NotificationContent': '.NotificationContent',
    'Widget': '.Widget',
    'Intents': '.SiriIntents',
    'BroadcastUpload': '.BroadcastUpload',
    'NotificationService': '.NotificationService',
}


def validate_configuration(config):
    if not isinstance(config, dict) or set(config) != set(VARIABLES):
        raise ValueError('CI configuration must contain exactly the documented build variables')
    if any(type(config[name]) is not kind for name, kind in VARIABLES.items()):
        raise ValueError('CI configuration variable types are invalid')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', config['telegram_bundle_id']):
        raise ValueError('Invalid bundle identifier')
    if not re.fullmatch(r'[A-Z0-9]{10}', config['telegram_team_id']):
        raise ValueError('Invalid team identifier')
    if not config['telegram_api_id'].isdigit() or int(config['telegram_api_id']) <= 0:
        raise ValueError('Invalid API identifier')
    if not re.fullmatch(r'[a-fA-F0-9]{32}', config['telegram_api_hash']):
        raise ValueError('Invalid API hash')
    if config['telegram_aps_environment'] not in ('production', 'development'):
        raise ValueError('Invalid push environment')
    if config['telegram_use_xcode_managed_codesigning']:
        raise ValueError('Reference builds require explicit ad-hoc signing')
    return config


def run(command):
    # Never print command input/configuration or captured output, which can contain build identity.
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{Path(command[0]).name} failed while preparing CI inputs')
    return result.stdout


def prepare(configuration, destination, bazel):
    config = validate_configuration(configuration)
    destination.mkdir(parents=True, exist_ok=True)
    os.chmod(destination, 0o700)
    for filename, content in {
        'WORKSPACE': '', 'MODULE.bazel': 'module(name = "build_configuration")\n', 'BUILD': ''
    }.items():
        (destination / filename).write_text(content)
    variables = 'telegram_bazel_path = ' + json.dumps(str(bazel.resolve())) + '\n'
    for name in sorted(config):
        value = repr(config[name]) if isinstance(config[name], bool) else json.dumps(config[name], ensure_ascii=False)
        variables += name + ' = ' + value + '\n'
    (destination / 'variables.bzl').write_text(variables)
    os.chmod(destination / 'variables.bzl', 0o600)
    profiles = destination / 'provisioning'
    profiles.mkdir(exist_ok=True)
    (profiles / 'BUILD').write_text('exports_files(glob(["*.mobileprovision"]))\n')
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    team = config['telegram_team_id']
    bundle = config['telegram_bundle_id']
    # These profiles satisfy build-time metadata requirements only. No Apple identity, private
    # signing certificate or real device UDID is used. The final reference IPA strips them.
    with tempfile.TemporaryDirectory(prefix='regram-ci-profile-') as temporary:
        work = Path(temporary)
        key, certificate, der = (work / name for name in ['key.pem', 'certificate.pem', 'certificate.der'])
        run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '730',
             '-subj', '/CN=Regram CI reference metadata', '-keyout', str(key), '-out', str(certificate)])
        run(['openssl', 'x509', '-in', str(certificate), '-outform', 'DER', '-out', str(der)])
        for name, suffix in PROFILE_SUFFIXES.items():
            entitlements = {
                'application-identifier': team + '.' + bundle + suffix,
                'com.apple.developer.team-identifier': team,
                'keychain-access-groups': [team + '.*'],
                'com.apple.security.application-groups': ['group.' + bundle],
                'aps-environment': config['telegram_aps_environment'],
                'get-task-allow': False,
                'com.apple.developer.usernotifications.communication': True,
            }
            if config['telegram_enable_siri']:
                entitlements['com.apple.developer.siri'] = True
            if config['telegram_enable_icloud']:
                entitlements.update({
                    'com.apple.developer.icloud-container-identifiers': ['iCloud.' + bundle],
                    'com.apple.developer.icloud-services': ['CloudDocuments'],
                    'com.apple.developer.ubiquity-kvstore-identifier': team + '.' + bundle,
                })
            payload = {
                'AppIDName': 'Regram CI reference', 'Name': 'Regram CI reference ' + name,
                'UUID': str(uuid.uuid4()).upper(), 'Version': 1, 'Platform': ['iOS'],
                'TeamIdentifier': [team], 'TeamName': 'CI reference metadata',
                'ApplicationIdentifierPrefix': [team], 'CreationDate': now,
                'ExpirationDate': now + datetime.timedelta(days=730),
                'DeveloperCertificates': [der.read_bytes()], 'Entitlements': entitlements,
                'ProvisionedDevices': ['0000000000000000000000000000000000000000'],
            }
            source = work / 'profile.plist'
            source.write_bytes(plistlib.dumps(payload))
            output = profiles / (name + '.mobileprovision')
            run(['openssl', 'cms', '-sign', '-binary', '-nodetach', '-in', str(source),
                 '-signer', str(certificate), '-inkey', str(key), '-outform', 'DER', '-out', str(output)])
    return destination


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--bazel', type=Path, required=True)
    args = parser.parse_args()
    # Use a generic error instead of exposing values from invalid JSON or signing metadata.
    try:
        prepare(json.loads(args.config.read_text()), args.output, args.bazel)
    except Exception:
        raise SystemExit('Could not prepare CI configuration; verify the encrypted build configuration Secret') from None
    print('Prepared ignored build configuration and seven synthetic reference profiles')


if __name__ == '__main__':
    main()

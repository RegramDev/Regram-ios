#!/usr/bin/env python3
"""Validate five private configurations without logging credentials."""
import argparse
import json
from pathlib import Path
from prepare import validate_configuration

IDENTITIES = {'Swiftgram': 'app.swiftgram.ios', 'Nicegram': 'app.nicegram', 'OLAI': 'com.olcorporation.olai', 'Turrit': 'com.seastar.turrit', 'Nagram': 'xyz.nextalone.nagram'}

def write_configurations(value, directory):
    if not isinstance(value, dict) or set(value) != set(IDENTITIES):
        raise ValueError('Exactly five named identity configurations are required')
    checked = {name: validate_configuration(config) for name, config in value.items()}
    for name, config in checked.items():
        if config['telegram_bundle_id'] != IDENTITIES[name]: raise ValueError('Bundle identity does not match variant')
    if len({(x['telegram_api_id'], x['telegram_api_hash']) for x in checked.values()}) != 5:
        raise ValueError('Five distinct API configurations are required')
    common = set(next(iter(checked.values()))) - {'telegram_bundle_id', 'telegram_api_id', 'telegram_api_hash'}
    for key in common:
        if len({json.dumps(config[key], sort_keys=True) for config in checked.values()}) != 1:
            raise ValueError('Signing and common build settings must remain consistent')
    directory.mkdir(parents=True, exist_ok=True); directory.chmod(0o700)
    for name, config in checked.items():
        path = directory / (name + '.json'); path.write_text(json.dumps(config, indent=2) + '\n'); path.chmod(0o600)
    return checked

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--config', type=Path, required=True); parser.add_argument('--output', type=Path, required=True); args = parser.parse_args()
    try: write_configurations(json.loads(args.config.read_text()), args.output)
    except Exception: raise SystemExit('Invalid private five-identity configuration; values were not logged') from None
    print('Validated five isolated identity configurations')

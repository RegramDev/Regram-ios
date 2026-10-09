#!/usr/bin/env python3
"""Package and validate a re-signable reference IPA without exposing CI configuration."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

from prepare import PROFILE_SUFFIXES


def run(args, cwd=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} failed during reference IPA validation')
    return result.stdout


def checksum(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def info(bundle):
    return plistlib.loads((bundle / 'Info.plist').read_bytes())


def extract(archive, directory):
    with zipfile.ZipFile(archive) as reader:
        if reader.testzip() is not None:
            raise RuntimeError('IPA archive is corrupt')
    run(['unzip', '-q', str(archive.resolve()), '-d', str(directory)])
    apps = list((directory / 'Payload').glob('*.app'))
    if len(apps) != 1:
        raise RuntimeError('IPA must contain exactly one app')
    return apps[0]


def package(ipa, symbols, destination, build_number, configuration):
    root = Path.cwd()
    config = json.loads(configuration.read_text())
    destination.mkdir(parents=True, exist_ok=True)
    version = json.loads((root / 'versions.json').read_text())['app']
    filename = f'Regram-{version}-b{build_number}-LCSign-reference.ipa'
    final = destination / filename
    if final.exists():
        raise RuntimeError('Refusing to replace an existing reference IPA')
    with tempfile.TemporaryDirectory(prefix='regram-ci-package-') as temporary:
        work = Path(temporary)
        staging = work / 'staging'
        app = extract(ipa, staging)
        bundles = [app] + sorted((app / 'PlugIns').glob('*.appex'))
        expected = {config['telegram_bundle_id'] + suffix for suffix in PROFILE_SUFFIXES.values()}
        if {info(b)['CFBundleIdentifier'] for b in bundles} != expected:
            raise RuntimeError('App and six extension identities must match the CI configuration')
        for bundle in bundles:
            metadata = info(bundle)
            if str(metadata['CFBundleVersion']) != str(build_number) or metadata['MinimumOSVersion'] != '15.0':
                raise RuntimeError('Unexpected build number or minimum iOS version')
        for profile in app.rglob('embedded.mobileprovision'):
            profile.unlink()
        for bundle in bundles[1:] + [app]:
            run(['codesign', '--force', '--sign', '-', '--preserve-metadata=identifier,entitlements,flags', str(bundle)])
        run(['codesign', '--verify', '--deep', '--strict', str(app)])
        archive = work / filename
        run(['zip', '-qry', str(archive), 'Payload'], cwd=staging)
        verified = extract(archive, work / 'verified')
        run(['codesign', '--verify', '--deep', '--strict', str(verified)])
        if list(verified.rglob('embedded.mobileprovision')):
            raise RuntimeError('Reference package must not contain provisioning profiles')
        catalog = root / 'Regram/RGTypography/RGFontCatalog.json'
        if checksum(verified / catalog.name) != checksum(catalog):
            raise RuntimeError('Font catalog does not match source')
        for entry in json.loads(catalog.read_text())['files']:
            if (verified / entry['file']).exists():
                raise RuntimeError('Downloadable fonts must not be embedded')
        for entry in json.loads((root / 'Regram/RGTypography/FONT-SOURCES.json').read_text())['files']:
            if entry['file'].startswith('Licenses/'):
                packed = verified / Path(entry['file']).name
                if not packed.exists() or checksum(packed) != entry['sha256']:
                    raise RuntimeError('Bundled font license does not match source')
        magic = {bytes.fromhex(value) for value in ['cffaedfe', 'feedfacf', 'cefaedfe', 'feedface', 'cafebabe', 'bebafeca']}
        uuids = {}
        for path in verified.rglob('*'):
            if not path.is_file():
                continue
            with path.open('rb') as stream:
                header = stream.read(4)
            if header not in magic:
                continue
            run(['codesign', '--verify', '--strict', str(path)])
            if run(['xcrun', 'lipo', '-archs', str(path)]).strip() != b'arm64':
                raise RuntimeError('Unexpected Mach-O architecture')
            uuids[str(path.relative_to(verified))] = run(['xcrun', 'dwarfdump', '--uuid', str(path)]).decode().split()[1]
        dsym_sources = sorted(symbols.glob('*.dSYM'))
        dsym_root = work / 'DSYMs'
        dsym_root.mkdir()
        symbol_uuids = set()
        for source in dsym_sources:
            shutil.copytree(source, dsym_root / source.name)
            for dwarf in (source / 'Contents/Resources/DWARF').iterdir():
                for line in run(['xcrun', 'dwarfdump', '--uuid', str(dwarf)]).decode().splitlines():
                    symbol_uuids.add(line.split()[1])
        if len(uuids) != 12 or len(dsym_sources) != 12 or not set(uuids.values()) <= symbol_uuids:
            raise RuntimeError('All 12 binaries must have matching debug symbols')
        symbol_archive = destination / f'Regram-{version}-b{build_number}.DSYMs.zip'
        run(['zip', '-qry', str(symbol_archive.resolve()), 'DSYMs'], cwd=work)
        shutil.move(archive, final)
    manifest = {
        'source_commit': run(['git', 'rev-parse', 'HEAD']).decode().strip(),
        'build_number': str(build_number), 'version': version, 'minimum_ios': '15.0',
        'extension_count': 6, 'macho_count': 12, 'dsym_count': 12, 'profile_count': 0,
        'signatures_and_architectures_verified': True, 'matching_debug_symbols': True,
        'font_catalog_and_licenses_verified': True, 'device_tested': False,
        'artifacts': {path.name: {'size_bytes': path.stat().st_size, 'sha256': checksum(path)} for path in [final, symbol_archive]},
    }
    (destination / 'BUILD-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Packaged and validated {filename}: main app, six extensions and 12 matching dSYMs')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--symbols', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--build-number', required=True)
    parser.add_argument('--configuration', type=Path, default=Path('build-input/ci/configuration.json'))
    args = parser.parse_args()
    package(args.ipa, args.symbols, args.output, args.build_number, args.configuration)

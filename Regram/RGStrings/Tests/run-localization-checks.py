"""Compile the production manager with local bundle/logging adapters; no network or account."""
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-localization-tests-') as directory:
    work = Path(directory)
    source = (root / 'Regram/RGStrings/Sources/LocalizationManager.swift').read_text()
    source = source.replace('import RGLogging\n', '').replace('import AppBundle\n', '')
    production = work / 'ProductionLocalization.swift'
    production.write_text(source)
    fixture = work / 'Fixture.bundle'
    fixture.mkdir()
    (fixture / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'regram.tests.localization', 'CFBundlePackageType': 'BNDL'}))
    for language in ['en', 'zh-hans', 'zh-hant']:
        target = fixture / (language + '.lproj')
        target.mkdir()
        strings = (root / 'Regram/RGStrings/Strings' / (language + '.lproj') / 'RGLocalizable.strings').read_text()
        if language == 'en':
            strings += '\n"Fixture.Format" = "%@ / %d";\n'
        (target / 'RGLocalizable.strings').write_text(strings)
    binary = work / 'localizations'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-DDEBUG', str(production), str(root / 'Regram/RGStrings/Tests/LocalizationManagerTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(fixture)], check=True)

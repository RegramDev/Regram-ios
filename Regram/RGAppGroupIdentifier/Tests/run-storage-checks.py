#!/usr/bin/env python3
"""Exercise production RG configuration storage and reset flags with synthetic data."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]

with tempfile.TemporaryDirectory(prefix='regram-storage-checks-') as temporary:
    work = Path(temporary)
    sources = [
        'submodules/TelegramCore/Sources/TelegramEngine/Utils/StringCodingKey.swift',
        'submodules/TelegramCore/Sources/SyncCore/SyncCore_JSON.swift',
        'Regram/RGWebSettingsScheme/Sources/File.swift',
        'Regram/RGGHSettingsScheme/Sources/RGGHSettingsScheme.swift',
        'submodules/TelegramCore/Sources/SyncCore/SyncCore_AppConfiguration.swift',
        'Regram/RGSimpleSettings/Sources/AppIconNames.swift',
    ]
    # Flatten imports only; all Codable and key-selection implementations remain production code.
    source = work / 'Storage.swift'
    source.write_text('import Foundation\n' + '\n'.join(
        '\n'.join(line for line in (ROOT / name).read_text().splitlines()
                  if not line.startswith('import ')) for name in sources
    ))
    for name, paths in [
        ('storage', [source, ROOT / 'Regram/RGAppGroupIdentifier/Tests/SettingsStorageTests.swift']),
        ('reset', [ROOT / 'Regram/RGDBReset/Sources/RGLaunchResetCoordinator.swift',
                   ROOT / 'Regram/RGDBReset/Tests/LaunchResetTests.swift']),
    ]:
        binary = work / name
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                        '-parse-as-library', *map(str, paths), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=20)

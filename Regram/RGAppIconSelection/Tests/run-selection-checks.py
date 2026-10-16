#!/usr/bin/env python3
"""Exercise the production persistence provider with the real icon coordinator and isolated defaults."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-icon-selection-') as temporary:
    work = Path(temporary)
    source = work/'Selection.swift'
    source.write_text((root/'Regram/RGAppIconSelection/Sources/RGAppIconSelectionStore.swift').read_text().replace('import RGSimpleSettings', ''))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library',
        str(root/'Regram/RGSimpleSettings/Sources/AppIconNames.swift'),
        str(root/'Regram/RGSimpleSettings/Sources/RGAppIconSwitchCoordinator.swift'), str(source),
        str(root/'Regram/RGAppIconSelection/Tests/SelectionPersistenceTests.swift'), '-o', str(work/'checks')], check=True)
    subprocess.run([str(work/'checks')], check=True, timeout=20)

#!/usr/bin/env python3
"""Run persistent production job/file handling with deterministic external URLSession I/O."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / 'Regram/RGAppUpdate'
with tempfile.TemporaryDirectory(prefix='regram-background-checks-') as temporary:
    binary = Path(temporary) / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', '-parse-as-library',
                    str(MODULE / 'Sources/RGUpdateRelease.swift'), str(MODULE / 'Sources/RGUpdateCache.swift'),
                    str(MODULE / 'Sources/RGUpdateBackgroundDownload.swift'),
                    str(MODULE / 'Tests/BackgroundDownloadTransport.swift'), str(MODULE / 'Tests/BackgroundDownloadTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)

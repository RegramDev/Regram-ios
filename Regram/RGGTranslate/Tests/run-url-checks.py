#!/usr/bin/env python3
"""Compile the production configuration and URL builder with account-free URL regressions."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'Regram/RGGTranslate/Sources/RGLLMTranslate.swift').read_text()
source = source.split('// MARK: - Concurrency', 1)[0].replace('import SwiftSignalKit\n', '')
with tempfile.TemporaryDirectory(prefix='regram-llm-url-') as directory:
    path = Path(directory)
    production = path / 'ProductionURL.swift'
    production.write_text(source)
    binary = path / 'url-checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', str(production), str(Path(__file__).with_name('URLTests.swift')), '-o', str(binary)], check=True, cwd=ROOT)
    subprocess.run([str(binary)], check=True, cwd=ROOT, env=os.environ)

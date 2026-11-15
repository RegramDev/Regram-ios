#!/usr/bin/env python3
"""Run the shipping native tokenizer/Core ML/projector on explicit local fixtures.

Nothing is fetched or uploaded. Put real-message fixtures and outputs in ignored build-input.
The same SemanticHarness.swift is used by the physical-device test app.
"""
import argparse
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[3]
p = argparse.ArgumentParser()
p.add_argument('--fixtures', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
p.add_argument('--resources', type=Path, default=root/'Regram/RGAdFilter/Resources')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
main = a.output/'SemanticMain.swift'
main.write_text('''import Foundation
@main enum Main {
    static func main() throws {
        try RGAdSemanticChecks.run(resources: URL(fileURLWithPath: CommandLine.arguments[1]), fixtures: URL(fileURLWithPath: CommandLine.arguments[2]), output: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("Native semantic report written; no message contents printed.")
    }
}
''')
exe = a.output/'semantic-checks'
subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '5', '-parse-as-library', *map(str, sorted((root/'Regram/RGAdFilter/Sources').glob('*.swift'))), str(root/'Regram/RGAdFilter/Tools/SemanticHarness.swift'), str(main), '-o', str(exe)], check=True)
subprocess.run([str(exe), str(a.resources.resolve()), str(a.fixtures.resolve()), str((a.output/'results.json').resolve())], check=True)

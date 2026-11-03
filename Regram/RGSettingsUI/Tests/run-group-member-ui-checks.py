#!/usr/bin/env python3
"""Exercise the production group-member controller with real signals and isolated UI/engine adapters."""
from pathlib import Path
import argparse, os, subprocess, tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", help="Run the navigation regression against a Git revision")
args = parser.parse_args()
relative = "Regram/RGSettingsUI/Sources/RGGroupMemberSettingsController.swift"
source = subprocess.check_output(["git", "show", args.baseline + ":" + relative], cwd=root, text=True) if args.baseline else (root / relative).read_text()
source = "\n".join(line for line in source.splitlines() if not line.startswith("import "))
source = "import Foundation\nimport SwiftSignalKit\n" + source.replace("public ", "")
with tempfile.TemporaryDirectory(prefix="regram-group-member-ui-") as directory:
    work = Path(directory)
    signals = sorted((root / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-emit-library", "-emit-module", "-module-name", "SwiftSignalKit", *map(str, signals), "-o", str(work / "libSwiftSignalKit.dylib")], check=True)
    production = work / "ProductionGroupMemberController.swift"
    production.write_text(source)
    binary = work / "checks"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-warnings-as-errors", "-I", str(work), "-L", str(work), "-lSwiftSignalKit", str(root / "Regram/RGSimpleSettings/Sources/GroupMemberSelection.swift"), str(production), str(root / "Regram/RGSettingsUI/Tests/GroupMemberUIAdapters.swift"), str(root / "Regram/RGSettingsUI/Tests/GroupMemberUIFlowTests.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env={**os.environ, "DYLD_LIBRARY_PATH": str(work)}, timeout=60)
    # Exercise the actual basic-group filter branch; an inner-loop continue used to keep duplicates.
    relative = "submodules/PeerInfoUI/Sources/ChannelMembersSearchControllerNode.swift"
    node = subprocess.check_output(["git", "show", args.baseline + ":" + relative], cwd=root, text=True) if args.baseline else (root / relative).read_text()
    start = node.index("case .ban, .select:")
    branch = node[start:node.index("case .promote:", start)]
    basic = work / "ProductionBasicMemberSelection.swift"
    basic.write_text((root / "Regram/RGSettingsUI/Tests/GroupMemberBasicSelectionTests.swift").read_text().replace("PRODUCTION_FILTER", branch))
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-warnings-as-errors", str(basic), "-o", str(work / "basic-checks")], check=True)
    subprocess.run([str(work / "basic-checks")], check=True)

#!/usr/bin/env python3
"""Check production iOS socket ownership and real loopback teardown in a booted simulator."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / "submodules/MtProtoKit/Sources"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="UUID of an already booted iOS simulator")
    parser.add_argument("--source", type=Path, default=SOURCES / "GCDAsyncSocket.m",
                        help="Socket implementation to check (also accepts a pre-fix source for regression verification)")
    parser.add_argument("--output", type=Path, default=ROOT / "build-input/cfstream-checks")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = args.source.resolve()
    environment = os.environ.copy()
    simulator_sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
                                            text=True, env=environment).strip()
    device_sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"],
                                         text=True, env=environment).strip()
    headers = ["-I", str(ROOT / "submodules/MtProtoKit/PublicHeaders"), "-I", str(SOURCES)]
    common = ["xcrun", "clang", "-fobjc-arc", "-fmodules", "-Werror", *headers]
    subprocess.run([*common, "-target", "arm64-apple-ios15.0", "-isysroot", device_sdk,
                    "-O2", "-c", str(source), "-o", str(output / "GCDAsyncSocket-arm64.o")],
                   check=True, env=environment)
    binary = output / "cfstream-checks"
    compile_command = [*common, "-target", "arm64-apple-ios15.0-simulator", "-isysroot", simulator_sdk,
                       "-framework", "Foundation", "-framework", "CFNetwork", "-framework", "Security",
                       '-DRG_SOCKET_SOURCE="' + str(source) + '"', "-x", "objective-c",
                       str(Path(__file__).with_name("GCDAsyncSocketStreamHarness.inc")),
                       str(SOURCES / "MTLogging.m"), "-o", str(binary)]
    (output / "compile-command.json").write_text(json.dumps(compile_command, indent=2) + "\n")
    subprocess.run(compile_command, check=True, env=environment)
    subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True, env=environment)
    subprocess.run(["xcrun", "simctl", "spawn", args.simulator, str(binary)],
                   check=True, timeout=60, env=environment)
    print("PASS: production arm64 iOS compilation (-O2, -Werror) and simulator regression checks")


if __name__ == "__main__":
    main()

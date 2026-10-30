#!/usr/bin/env python3
"""Run signing tools without publishing certificate, profile, or account diagnostics."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    directory = Path(os.environ.get("RUNNER_TEMP", "build-input/testflight"))
    directory.mkdir(parents=True, exist_ok=True)
    # Tool output may contain encoded profiles or whole certificate subjects.
    # Keep it private even on failure; exit status and step name identify the failure.
    with tempfile.TemporaryFile(dir=directory) as log:
        process = subprocess.Popen(sys.argv[1:], stdout=log, stderr=subprocess.STDOUT)
        try:
            while True:
                try:
                    code = process.wait(timeout=60)
                    break
                except subprocess.TimeoutExpired:
                    print("Private build/signing operation is still running", flush=True)
        except BaseException:
            process.terminate()
            process.wait()
            raise
        if code:
            print(f"Private build/signing operation failed (exit {code}); diagnostics were withheld to protect signing identity.")
        return code


if __name__ == "__main__":
    raise SystemExit(main())

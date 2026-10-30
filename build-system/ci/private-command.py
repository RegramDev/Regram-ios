#!/usr/bin/env python3
"""Run signing tools without publishing certificate, profile, or account diagnostics."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path("build-input/testflight")
# Generic certificate words that identify nothing and appear in ordinary tool paths.
GENERIC_WORDS = {"apple", "distribution", "development", "developer", "iphone", "ios"}
INTERESTING = re.compile(r"\b(error|fatal|failed|failure|killed|denied|exceeded|no space|errSec\w*)\b", re.I)
UNSAFE = re.compile(r"[A-Za-z0-9+/=]{60,}|-----BEGIN|<\?xml|<plist|<key>")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+")


def private_values():
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes

    values = {os.environ.get(name, "") for name in ("APPLE_TEAM_ID", "ASC_APP_ID", "ASC_KEY_ID", "ASC_ISSUER_ID")}
    certificate = x509.load_der_x509_certificate((ROOT / "distribution.cer").read_bytes())
    for attribute in certificate.subject:
        value = str(attribute.value)
        if len(value) >= 3:
            values.add(value)
        # Also hide partial forms such as the organization name without its suffix.
        values.update(word for word in re.findall(r"[^\W_]{3,}", value) if word.lower() not in GENERIC_WORDS)
    for algorithm in (hashes.SHA1(), hashes.SHA256()):
        values.add(certificate.fingerprint(algorithm).hex())
    for value in json.loads((ROOT / "configuration.json").read_text()).values():
        if isinstance(value, str) and len(value) >= 6:
            values.add(value)
    return sorted((value for value in values if value), key=len, reverse=True)


def redact(line, values):
    for value in values:
        line = re.sub(re.escape(value), "***", line, flags=re.I)
    # Tool output must never be able to issue GitHub workflow commands.
    return EMAIL.sub("***", line).replace("::", ": :")


def summary(log, limit_head=25, limit_tail=15):
    """Return redacted error lines, or None when redaction inputs are unavailable."""
    try:
        values = private_values()
    except Exception:
        return None
    log.seek(0)
    lines, seen = [], set()
    for raw in log:
        line = raw.decode("utf-8", "replace").strip()
        if not INTERESTING.search(line) or UNSAFE.search(line):
            continue
        line = redact(line, values)[:300]
        if line not in seen:
            seen.add(line)
            lines.append(line)
    if len(lines) > limit_head + limit_tail:
        lines = lines[:limit_head] + ["..."] + lines[-limit_tail:]
    return lines


def main():
    directory = Path(os.environ.get("RUNNER_TEMP", "build-input/testflight"))
    directory.mkdir(parents=True, exist_ok=True)
    # Tool output may contain encoded profiles or whole certificate subjects. Only
    # error lines are shown on failure, after removing every known private value.
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
            print(f"Private build/signing operation failed (exit {code}).")
            lines = summary(log)
            if lines is None:
                print("Diagnostics were withheld because private values could not be loaded for redaction.")
            else:
                print("Redacted error lines:" if lines else "No error lines were reported.")
                for line in lines:
                    print("  " + line)
        return code


if __name__ == "__main__":
    raise SystemExit(main())

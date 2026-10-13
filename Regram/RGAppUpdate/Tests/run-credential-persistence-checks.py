#!/usr/bin/env python3
"""Build production credential storage into an isolated simulator app; no real certificates.
Pass the UDID of a booted test simulator. DEVELOPER_DIR selects the Xcode toolchain.
"""
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
DEVICE = sys.argv[1]
BUNDLE = 'app.regram.tests.update-credentials'

def run(*args):
    return subprocess.check_output(args, text=True).strip()

with tempfile.TemporaryDirectory(prefix='regram-credentials-') as temporary:
    app = pathlib.Path(temporary) / 'CredentialChecks.app'
    app.mkdir()
    info = dict(CFBundleIdentifier=BUNDLE, CFBundleExecutable='CredentialChecks', CFBundleName='Credential Checks', CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion='15.0', UIDeviceFamily=[1, 2], UILaunchScreen={}, LSRequiresIPhoneOS=True)
    plist = app / 'Info.plist'
    plist.write_bytes(plistlib.dumps(info))
    entitlements = pathlib.Path(temporary)/'entitlements.plist'
    identity = 'TESTREGRAM.' + BUNDLE
    entitlements.write_bytes(plistlib.dumps({'application-identifier': identity, 'keychain-access-groups': [identity]}))
    sources = ROOT / 'Regram/RGAppUpdate'
    # Simulator securityd reads the embedded entitlement section, as Xcode's
    # simulator linker does; an ad-hoc signing blob alone is insufficient.
    run('xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-sdk', run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'), '-target', 'arm64-apple-ios15.0-simulator', '-parse-as-library', str(sources/'Sources/RGUpdateKeychain.swift'), str(sources/'Sources/RGUpdateIdentity.swift'), str(sources/'Tests/CredentialPersistenceHost.swift'), '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__entitlements', '-Xlinker', str(entitlements), '-o', str(app/'CredentialChecks'))
    run('codesign', '--force', '--sign', '-', str(app))
    run('xcrun', 'simctl', 'install', DEVICE, str(app))
    try:
        for index, mode in enumerate(['store', 'verify', 'verify', 'legacy-store', 'legacy-verify', 'erase']):
            if index == 2:
                info['CFBundleVersion'] = '2'
                plist.write_bytes(plistlib.dumps(info))
                run('codesign', '--force', '--sign', '-', str(app))
                run('xcrun', 'simctl', 'install', DEVICE, str(app))
            container = pathlib.Path(run('xcrun', 'simctl', 'get_app_container', DEVICE, BUNDLE, 'data'))
            result = container/'Documents/result.txt'
            result.unlink(missing_ok=True)
            run('xcrun', 'simctl', 'launch', DEVICE, BUNDLE, mode)
            deadline = time.monotonic() + 30
            while not result.exists() and time.monotonic() < deadline:
                time.sleep(0.2)
            assert result.exists(), f'{mode}: process did not report a result'
            actual = result.read_text()
            assert actual == 'PASSED: ' + mode, actual
            print(actual + (' after reinstall' if index == 2 else ''), flush=True)
            run('xcrun', 'simctl', 'terminate', DEVICE, BUNDLE)
    finally:
        run('xcrun', 'simctl', 'uninstall', DEVICE, BUNDLE)

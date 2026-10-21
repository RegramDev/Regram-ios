#!/usr/bin/env python3
"""Compile production schema/coordinator against controllable external ActivityKit/UIKit adapters."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / 'Regram/RGAppUpdate'
with tempfile.TemporaryDirectory(prefix='regram-activity-checks-') as temporary:
    directory = Path(temporary)
    def module(name, paths, links=()):
        subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', '-emit-module', '-emit-library', '-module-name', name, '-I', temporary, '-L', temporary, *links, *map(str, paths), '-o', str(directory / ('lib' + name + '.dylib'))], check=True)
    module('ActivityKit', [MODULE / 'Tests/LiveActivityKitFixture.swift'])
    (directory / 'UIKit.swift').write_text('import Foundation\n@MainActor public final class UIApplication { public enum State { case active, background }; public static let shared = UIApplication(); public var applicationState = State.active }\n')
    module('UIKit', [directory / 'UIKit.swift'])
    (directory / 'RGStrings.swift').write_text('public extension String { func i18n(_ code: String) -> String { self } }\n')
    module('RGStrings', [directory / 'RGStrings.swift'])
    (directory / 'BuildConfig.swift').write_text('public final class BuildConfig { public init(baseAppBundleId: String) {} ; public var appSpecificUrlScheme: String { "rg" } }\n')
    module('BuildConfig', [directory / 'BuildConfig.swift'])
    module('RGUpdateActivity', [ROOT / 'Regram/RGUpdateActivity/Sources/RGUpdateActivityAttributes.swift'], ['-lActivityKit'])
    binary = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', '-parse-as-library', '-I', temporary, '-L', temporary,
                    '-lActivityKit', '-lUIKit', '-lRGStrings', '-lRGUpdateActivity', '-lBuildConfig',
                    str(MODULE / 'Sources/RGUpdateRelease.swift'), str(MODULE / 'Sources/RGUpdateLiveActivity.swift'), str(MODULE / 'Sources/RGUpdateSettingsLink.swift'),
                    str(MODULE / 'Tests/LiveActivityTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20, env={**__import__('os').environ, 'DYLD_LIBRARY_PATH': temporary})

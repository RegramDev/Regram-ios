#!/usr/bin/env python3
"""Compile production settings with isolated preference suites and external logging/group adapters."""
from pathlib import Path
import os, subprocess, tempfile, uuid
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-settings-checks-') as directory:
 work=Path(directory)
 env=dict(os.environ,RG_TEST_SUITE='app.regram.tests.'+str(uuid.uuid4()))
 modules={
  'RGAppGroupIdentifier':'import Foundation\npublic func rgSharedUserDefaults() -> UserDefaults? { UserDefaults(suiteName: ProcessInfo.processInfo.environment["RG_TEST_SUITE"]! + "-group") }\npublic func rgResolvedAppGroupIdentifier() -> String? { "test-group" }\n',
  'RGLogging':'public final class RGLogger { public static let shared = RGLogger(); public func log(_ name: String, _ text: String) {} }\n'
 }
 for name,source in modules.items():
  path=work/(name+'.swift');path.write_text(source)
  subprocess.run(['xcrun','swiftc','-swift-version','5','-emit-library','-emit-module','-module-name',name,str(path),'-emit-module-path',str(work/(name+'.swiftmodule')),'-o',str(work/('lib'+name+'.dylib'))],check=True)
 sources=[]
 for path in sorted((root/'Regram/RGSimpleSettings/Sources').glob('*.swift')):
  destination=work/path.name
  # Only the backing-store access is adapted, preserving production caching, migrations and logic.
  destination.write_text(path.read_text().replace('UserDefaults.standard','UserDefaults.rgTestStandard').replace('?? .standard','?? .rgTestStandard').replace('= .standard','= .rgTestStandard').replace('return .standard','return .rgTestStandard'))
  sources.append(str(destination))
 command=['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-I',str(work),'-L',str(work),'-lRGAppGroupIdentifier','-lRGLogging','-Xlinker','-rpath','-Xlinker',str(work)]+sources+[str(root/'Regram/RGSimpleSettings/Tests/SettingsRuntimeTests.swift'),'-o',str(work/'tests')]
 subprocess.run(command,check=True,env=env)
 subprocess.run([str(work/'tests')],check=True,env=env,timeout=90)

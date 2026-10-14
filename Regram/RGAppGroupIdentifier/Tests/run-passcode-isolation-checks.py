from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/PasscodeCore/Sources/Passcode.swift').read_text()
a = source.index('    private func service(_ account: String)')
b = source.index('\n    func read(', a)
method = source[a:b].replace('private func service', 'func service')
method = method.replace('        #if os(macOS)\n        return PasscodeKeychainScope.service(service, environment: self.environment)\n        #else\n', '').replace('        #endif\n', '')
fixture = '''import Foundation
struct Environment {let keychainScope:String?;func biometricKeychainService() throws ->String {"biometric"}}
struct Store {let environment:Environment
'''
tests = '''
}
@main enum Tests {static func main() throws {
 var services=Set<String>()
 for scope in [nil,"app.nicegram","com.olcorporation.olai","com.seastar.turrit","xyz.nextalone.nagram"] {
  let store=Store(environment:Environment(keychainScope:scope));let service=try store.service("credential");services.insert(service)
  if scope == nil {precondition(service=="org.telegram.passcode.v1")}
  else {precondition(service=="org.telegram.scoped."+scope!+"/org.telegram.passcode.v1")}
 }
 precondition(services.count==5)
 print("Production iOS passcode services isolate five identities and retain the base package legacy service.")
}}
'''
with tempfile.TemporaryDirectory(prefix='regram-passcode-isolation-') as directory:
    path = Path(directory)
    (path / 'Tests.swift').write_text(fixture + method + tests)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                    str(path / 'Tests.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)

for name in ['Telegram/Share/ShareRootController.swift', 'Telegram/SiriIntents/IntentHandler.swift',
             'Telegram/WidgetKitWidget/TodayViewController.swift', 'Telegram/NotificationService/Sources/NotificationService.swift',
             'Telegram/NotificationContent/NotificationViewController.swift', 'submodules/TelegramUI/Sources/AppDelegate.swift']:
    assert 'keychainScope: RGStorageScope.keychainScope' in (root / name).read_text(), name
print('Main app and every passcode-aware extension use the same identity scope.')

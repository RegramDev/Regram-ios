#!/usr/bin/env python3
"""Exercise the production attachment gate for the named settings-import menu action."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift').read_text()
start = source.index('private func rgSettingsBackupExportFile(')
end = source.index('\nprivate func rgImportSettingsBackup(', start)
gate = source[start:end]
backup = (root / 'Regram/RGSimpleSettings/Sources/SettingsBackup.swift').read_text()
a = backup.index('    public static func isExportFileName(')
b = backup.index('\n    public static func read(', a)
filename = backup[a:b]
fixture = r'''
import Foundation
struct EngineRawMessage { let media: [Any]; let containsSecretMedia: Bool }
final class TelegramMediaFile {
    let fileName: String?; let size: Int64?
    init(_ name: String?, _ size: Int64? = 20) { fileName = name; self.size = size }
}
enum RGSettingsBackup {
    static let maximumBytes = 2 * 1024 * 1024
    FILENAME
}
GATE
@main enum Checks {
    static func main() {
        func message(_ name: String?, size: Int64? = 20, secret: Bool = false) -> EngineRawMessage { EngineRawMessage(media: [TelegramMediaFile(name, size)], containsSecretMedia: secret) }
        for name in ["regram-settings.json", "Regram-Settings (2).JSON"] { precondition(rgSettingsBackupExportFile(in: [message(name)]) != nil) }
        for name in [nil, "data.json", "regram-message-filter.json", "regram-settings.json.zip"] as [String?] { precondition(rgSettingsBackupExportFile(in: [message(name)]) == nil) }
        precondition(rgSettingsBackupExportFile(in: []) == nil)
        precondition(rgSettingsBackupExportFile(in: [message("regram-settings.json"), message("regram-settings.json")]) == nil)
        precondition(rgSettingsBackupExportFile(in: [message("regram-settings.json", size: Int64(RGSettingsBackup.maximumBytes + 1))]) == nil)
        precondition(rgSettingsBackupExportFile(in: [message("regram-settings.json", secret: true)]) == nil)
        precondition(rgSettingsBackupExportFile(in: [message("regram-settings.json", size: nil)]) != nil)
        print("Settings import menu passed: known filename, copy suffix, generic/filter JSON exclusion, single-file/secret-media/size boundaries.")
    }
}
'''.replace('FILENAME', filename).replace('GATE', gate)
with tempfile.TemporaryDirectory(prefix='regram-settings-import-') as directory:
    work = Path(directory); swift = work/'Checks.swift'; swift.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work/'checks')], check=True)
    subprocess.run([str(work/'checks')], check=True)

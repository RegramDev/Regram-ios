#!/usr/bin/env python3
"""Exercise the production preview layout with isolated settings and a fixed pixel scale."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
helper = (root/'Regram/RGChatListSimpleSettingsSignal/Sources/RGCompactMessagePreviewLayout.swift').read_text().replace('import RGSimpleSettings', '').replace('import Display', '')
source = '''import Foundation
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var chatListLines = "2"
    enum ChatListLines: String { case one = "1", two = "2" }
}
func floorToScreenPixels(_ value: CGFloat) -> CGFloat { floor(value * 2) / 2 }
''' + helper + '''
@main enum Checks { static func main() {
    for (setting, count) in [("1", 1), ("2", 2), ("3", 2)] {
        RGSimpleSettings.shared.chatListLines = setting
        precondition(RGCompactMessagePreviewLayout.maximumMessageLines() == count)
        precondition(RGCompactMessagePreviewLayout.isEnabled() == (count == 1))
        for factor: CGFloat in [0.7, 1, 1.5, 2] {
            for author in [false, true] { for compact in [false, true] { for tags in [false, true] {
                let title = 20 * factor, authorHeight = author ? 20 * factor : 0
                let body = CGFloat(count) * 20 * factor
                let offset = RGCompactMessagePreviewLayout.textBlockOffset(sizeFactor: factor, compactMessagePreview: count == 1, compactChatList: compact, hasAuthorLine: author)
                let minimum = RGCompactMessagePreviewLayout.minimumRowHeight(titleHeight: title, authorHeight: authorHeight, bodyHeight: body, sizeFactor: factor, compactMessagePreview: count == 1, compactChatList: compact, hasTags: tags)
                let bodyBottom = floorToScreenPixels(8 * factor) + title - 2 + (author ? authorHeight - 3 : 0) + offset + body
                precondition(minimum >= bodyBottom + (tags ? floorToScreenPixels(22 * factor) : 0) + 5.5)
            } } }
        }
    }
    print("Preview layout passed: 1/2 lines, legacy fallback, sender rows, tags, compact mode and enlarged fonts.")
} }
'''
with tempfile.TemporaryDirectory(prefix='regram-preview-lines-') as temporary:
    folder = Path(temporary)
    path = folder/'Checks.swift'; path.write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library', str(path), '-o', str(folder/'checks')], check=True)
    subprocess.run([str(folder/'checks')], check=True)

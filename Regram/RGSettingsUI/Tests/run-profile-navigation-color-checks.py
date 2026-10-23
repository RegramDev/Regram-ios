#!/usr/bin/env python3
"""Exercise the production glass-change callback with native-theme and custom-node adapters."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true', help='Compare the committed source with uncommitted edits')
args = parser.parse_args()
path = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift'
source = subprocess.check_output(['git', 'show', 'HEAD:' + path], cwd=root, text=True) if args.baseline else (root / path).read_text()
start = source.index('    private func applyNavigationGlass(')
end = source.index('\n    /// A bar button', start)
callback = source[start:end].replace('private func', 'func', 1)
fixture = r'''
import Foundation
enum UIColor: Equatable { case black, white }
enum ContainedViewLayoutTransition { case immediate }
enum PeerInfoNavigationGlass: Equatable { case plain, tinted(Int) }
final class Theme {
    let buttonColor: UIColor
    init(_ color: UIColor) { buttonColor = color }
}
final class Strings {
    let Common_Back: String, PeerInfo_QRCode_Title: String
    init(_ back: String = "Back", _ qr: String = "QR") { Common_Back = back; PeerInfo_QRCode_Title = qr }
}
struct PresentationData { var theme = Theme(.black); var strings = Strings() }
struct NavigationBarPresentationData {
    let theme: Theme, strings: Strings
    init(presentationData: PresentationData) { theme = presentationData.theme; strings = presentationData.strings }
    init(theme: Theme, strings: Strings) { self.theme = theme; self.strings = strings }
}
// The native resolver already colors standard bar items correctly. These adapters
// expose that result while testing delivery to the two custom node types.
func peerInfoNavigationBarTheme(glass: PeerInfoNavigationGlass, base: Theme) -> Theme {
    switch glass { case .plain: return base; case .tinted: return Theme(.white) }
}
enum PresentationResourcesRootController {
    static func navigationBackIcon(_ theme: Theme) -> Int? { 1 }
    static func navigationQrCodeIcon(_ theme: Theme) -> Int? { 2 }
}
final class Bar {
    var color: UIColor?
    var updates = 0
    func updatePresentationData(_ data: NavigationBarPresentationData, transition: ContainedViewLayoutTransition) { color = data.theme.buttonColor; updates += 1 }
}
final class Controller { var navigationBar: Bar? = Bar() }
final class Leading {
    var color: UIColor = .white
    var backTitle = "", qrTitle = ""
    func update(backImage: Int?, qrImage: Int?, color: UIColor, backTitle: String, qrTitle: String) {
        precondition(backImage == 1 && qrImage == 2)
        self.color = color; self.backTitle = backTitle; self.qrTitle = qrTitle
    }
}
final class Icon {
    var color: UIColor = .white
    func updateContentsColor(_ color: UIColor, transition: ContainedViewLayoutTransition) { self.color = color }
}
struct Items { var appliedSlotKey: Int? = 1 }
final class Screen {
    var controller: Controller? = Controller()
    var presentationData = PresentationData()
    var appliedNavigationGlass: (glass: PeerInfoNavigationGlass, theme: Theme, strings: Strings)?
    var navigationButtonColor: UIColor?
    var navigationIconButtonColor: UIColor? = .white
    var rgSettingsLeadingButtons: (node: Leading, item: Int)? = (Leading(), 1)
    var navigationItems = Items()
    let navigationIconButton = Icon()
    CALLBACK
}
@main enum Checks {
    static func main() {
        let screen = Screen()
        func change(_ glass: PeerInfoNavigationGlass, _ expected: UIColor) {
            screen.applyNavigationGlass(glass, transition: .immediate)
            precondition(screen.controller!.navigationBar!.color == expected)
            precondition(screen.rgSettingsLeadingButtons!.node.color == expected, "Back and QR retained a stale color")
            precondition(screen.navigationIconButton.color == expected, "Animated search/more retained a stale color")
        }
        change(.tinted(1), .white)
        change(.plain, .black) // Scroll the colored profile cover away to the white bar.
        let count = screen.controller!.navigationBar!.updates
        change(.plain, .black)
        precondition(screen.controller!.navigationBar!.updates == count, "Do not recolor every scroll frame")
        change(.tinted(2), .white)
        change(.plain, .black)
        screen.presentationData.theme = Theme(.white)
        change(.plain, .white) // Same glass state, new dark theme.
        screen.presentationData.theme = Theme(.black)
        screen.presentationData.strings = Strings("返回", "二维码")
        change(.plain, .black)
        precondition(screen.rgSettingsLeadingButtons!.node.backTitle == "返回" && screen.rgSettingsLeadingButtons!.node.qrTitle == "二维码")
        screen.navigationItems.appliedSlotKey = nil
        screen.navigationIconButton.color = .black
        changeLeadingOnly(screen)
        precondition(screen.navigationIconButton.color == .black, "Keep the native leaving icon transition")
        print("Profile navigation colors: cover/white background transitions, dark/light themes, locale refresh, update coalescing and leaving icons passed")
    }
    static func changeLeadingOnly(_ screen: Screen) {
        screen.applyNavigationGlass(.tinted(3), transition: .immediate)
        precondition(screen.rgSettingsLeadingButtons!.node.color == .white)
    }
}
'''.replace('CALLBACK', callback)
with tempfile.TemporaryDirectory(prefix='regram-profile-navigation-color-') as directory:
    work = Path(directory)
    swift = work / 'Checks.swift'
    swift.write_text(fixture)
    binary = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

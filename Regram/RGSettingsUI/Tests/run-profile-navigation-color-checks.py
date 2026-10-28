#!/usr/bin/env python3
"""Check profile color delivery, optionally including the real UIKit CGImage rendering boundary."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true', help='Compare the committed source with uncommitted edits')
parser.add_argument('--simulator', metavar='UDID', help='Also run image pixel checks on this booted iOS simulator')
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

if args.simulator:
    # ASImageNode consumes the CGImage, bypassing UIImage.draw/UIImageView tint handling.
    # Keep that boundary explicit: callback/color-value tests alone missed this regression.
    image_node = (root / 'submodules/Display/Source/Nodes/ASImageNode.swift').read_text()
    assert 'self.contents = image.cgImage' in image_node
    node_path = 'Regram/RGSettingsUI/Sources/RGSettingsLeadingButtonsNode.swift'
    node = subprocess.check_output(['git', 'show', 'HEAD:' + node_path], cwd=root, text=True) if args.baseline else (root / node_path).read_text()
    update = node[node.index('    public func update(backImage:'):node.index('\n    public override func calculateSizeThatFits(')]
    drawing = (root / 'submodules/Display/Source/GenerateImage.swift').read_text()
    tint = drawing[drawing.index('public func generateTintedImage('):drawing.index('\npublic func generateGradientTintedImage(')]
    render_fixture = r'''
import UIKit
import CoreImage
TINT
// Only the button's storage is adapted. UIImage, CoreGraphics, the production
// update method and Telegram's production bitmap tint function execute on iOS.
final class Button {
    var image: UIImage?
    var accessibilityLabel: String?
    func setImage(_ image: UIImage?, for state: UIControl.State) {
        precondition(state == .normal)
        self.image = image
    }
}
final class Leading {
    let backButton = Button(), qrButton = Button()
    UPDATE
}
func require(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("Profile navigation rendering failed: \(message)\n", stderr)
        exit(1)
    }
}
func pdfImage(_ path: String) -> UIImage {
    let page = CGPDFDocument(URL(fileURLWithPath: path) as CFURL)!.page(at: 1)!
    let rect = page.getBoxRect(.mediaBox)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2.0
    return UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
        let context = renderer.cgContext
        context.translateBy(x: 0.0, y: rect.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.drawPDFPage(page)
    }
}
func requirePixels(_ image: UIImage?, rgb: [UInt8], name: String) {
    guard let bitmap = image?.cgImage else {
        require(false, "\(name) has no bitmap for ASImageNode")
        return
    }
    let width = bitmap.width, height = bitmap.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var solidPixels = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] == 255 {
        solidPixels += 1
        require(Array(pixels[offset ..< offset + 3]) == rgb, "\(name) CGImage pixels stayed \(Array(pixels[offset ..< offset + 3])) instead of \(rgb)")
    }
    require(solidPixels > 10, "\(name) lost its glyph")
}
@main enum RenderChecks {
    static func main() {
        // The production resource functions cache white versions of both glyphs.
        let back = generateTintedImage(image: pdfImage(CommandLine.arguments[1]), color: .white)!
        let qr = generateTintedImage(image: pdfImage(CommandLine.arguments[2]), color: .white)!
        let node = Leading()
        for (color, pixels) in [(UIColor.white, [UInt8](repeating: 255, count: 3)), (.black, [0, 0, 0]), (.white, [255, 255, 255]), (.black, [0, 0, 0])] {
            node.update(backImage: back, qrImage: qr, color: color, backTitle: "返回", qrTitle: "二维码")
            requirePixels(node.backButton.image, rgb: pixels, name: "Back")
            requirePixels(node.qrButton.image, rgb: pixels, name: "QR")
            require(node.backButton.image?.size == back.size && node.qrButton.image?.size == qr.size, "Glyph sizes changed")
        }
        require(node.backButton.accessibilityLabel == "返回" && node.qrButton.accessibilityLabel == "二维码", "Labels changed")
        node.update(backImage: nil, qrImage: nil, color: .black, backTitle: "Back", qrTitle: "QR")
        require(node.backButton.image == nil && node.qrButton.image == nil, "Missing images left stale glyphs")
        print("Profile navigation UIKit rendering passed: real Back/QR PDF assets, opaque CGImage pixels across white/black/white/black, dimensions, labels and nil images")
    }
}
'''.replace('TINT', tint).replace('UPDATE', update)
    with tempfile.TemporaryDirectory(prefix='regram-profile-navigation-render-') as directory:
        work = Path(directory)
        swift, binary = work / 'RenderChecks.swift', work / 'render-checks'
        swift.write_text(render_fixture)
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
        subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-swift-version', '5', '-parse-as-library', '-target', 'arm64-apple-ios15.0-simulator', '-sdk', sdk, str(swift), '-o', str(binary)], check=True)
        assets = root / 'submodules/TelegramUI/Images.xcassets'
        subprocess.run(['xcrun', 'simctl', 'spawn', args.simulator, str(binary), str(assets / 'Navigation/Back.imageset/headerback_30.pdf'), str(assets / 'Settings/QrIcon.imageset/qr_30.pdf')], check=True, timeout=60)

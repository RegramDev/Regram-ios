import XCTest
import UIKit
import RGTypography
import RGSimpleSettings
import Display

final class TypographyTests: XCTestCase {
    private var original: RGFontConfiguration!
    override func setUp() {
        super.setUp()
        self.original = RGSimpleSettings.shared.fontConfiguration
    }
    override func tearDown() {
        RGSimpleSettings.shared.fontChineseFamily = self.original.chineseFamily.rawValue
        RGSimpleSettings.shared.fontFamily = self.original.family.rawValue
        RGSimpleSettings.shared.fontApplyToMessages = self.original.messages
        RGSimpleSettings.shared.fontApplyToInterface = self.original.interface
        super.tearDown()
    }

    func testEveryBundledFaceLoadsFromAppResources() {
        for family in RGFontFamily.allCases.filter({ $0.bundledPrefix != nil }) {
            for weight in [UIFont.Weight.regular, .medium, .semibold, .bold] {
                let font = RGTypography.font(family: family, size: 19, weight: weight)
                XCTAssertNotNil(font, "Bundled font \(family)/\(weight) must load")
                XCTAssertEqual(font?.pointSize, 19)
                XCTAssertTrue(font?.fontName.hasPrefix(family.bundledPrefix! + "-") == true)
            }
            for weight in [UIFont.Weight.regular, .bold] {
                let font = RGTypography.font(family: family, size: 19, weight: weight, italic: true)
                XCTAssertNotNil(font)
                XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true || (font?.fontDescriptor.matrix.c ?? 0) != 0, "Italic emphasis must survive font selection")
            }
        }
    }

    func testAreasAndCacheRespondImmediately() {
        let settings = RGSimpleSettings.shared
        settings.fontFamily = RGFontFamily.system.rawValue
        settings.fontChineseFamily = RGChineseFontFamily.system.rawValue
        let system = Font.regular(17).fontName
        let fixed = Font.monospace(17).fontName
        settings.fontApplyToInterface = true
        settings.fontApplyToMessages = false
        settings.fontFamily = RGFontFamily.jetBrainsMono.rawValue
        XCTAssertEqual(Font.regular(17).fontName, "JetBrainsMono-Regular")
        XCTAssertEqual(Font.bold(17).fontName, "JetBrainsMono-Bold")
        XCTAssertEqual(Font.italic(17).fontName, "JetBrainsMono-Italic")
        XCTAssertFalse(Font.with(size: 17, area: .messages).fontName.hasPrefix("JetBrains"))
        XCTAssertEqual(Font.monospace(17).fontName, fixed)
        XCTAssertFalse(Font.with(size: 53, area: .system).fontName.hasPrefix("JetBrains"))
        settings.fontApplyToInterface = false
        settings.fontApplyToMessages = true
        XCTAssertEqual(Font.regular(17).fontName, system)
        XCTAssertEqual(Font.with(size: 17, area: .messages).fontName, "JetBrainsMono-Regular")
        settings.fontFamily = RGFontFamily.inter.rawValue
        XCTAssertEqual(Font.with(size: 17, area: .messages).fontName, "Inter-Regular", "A cached font must not survive a family change")
        settings.fontApplyToMessages = false
        XCTAssertFalse(Font.with(size: 17, area: .messages).fontName.hasPrefix("Inter-"))
    }

    func testSettingsPublishChangesAndPersistSelections() {
        let settings = RGSimpleSettings.shared
        settings.fontFamily = RGFontFamily.system.rawValue
        settings.fontApplyToMessages = true
        settings.fontApplyToInterface = true
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: RGFontConfiguration.settingsChanged, object: nil, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        settings.fontFamily = RGFontFamily.jetBrainsMonoNL.rawValue
        settings.fontApplyToMessages = false
        settings.fontApplyToInterface = false
        XCTAssertEqual(notifications, 3)
        settings.fontApplyToInterface = false
        XCTAssertEqual(notifications, 3, "An unchanged setting must not relayout the app")
        XCTAssertEqual(UserDefaults.standard.string(forKey: RGSimpleSettings.Keys.fontFamily.rawValue), RGFontFamily.jetBrainsMonoNL.rawValue)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: RGSimpleSettings.Keys.fontApplyToMessages.rawValue))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: RGSimpleSettings.Keys.fontApplyToInterface.rawValue))
    }

    func testChangingChineseDoesNotReplaceTheLatinFace() {
        let settings = RGSimpleSettings.shared
        settings.fontApplyToMessages = true
        settings.fontApplyToInterface = true
        settings.fontFamily = RGFontFamily.jetBrainsMono.rawValue
        settings.fontChineseFamily = RGChineseFontFamily.ibmPlexSansSC.rawValue
        let first = Font.regular(17)
        settings.fontChineseFamily = RGChineseFontFamily.notoSerifSC.rawValue
        let second = Font.regular(17)
        XCTAssertEqual(first.fontName, second.fontName)
        XCTAssertFalse(first === second, "The Chinese selection must create a new cached composite")
        settings.fontFamily = RGFontFamily.system.rawValue
        XCTAssertNotNil(RGTypography.font(configuration: settings.fontConfiguration, size: 17), "Chinese-only configuration must still compose a font")
    }

    func testChineseEmojiAndMixedFormattingRender() {
        let text = NSMutableAttributedString(string: "Hello 中文 😀 0123456789", attributes: [.font: RGTypography.font(family: .jetBrainsMono, size: 19)!])
        text.append(NSAttributedString(string: " Bold", attributes: [.font: RGTypography.font(family: .jetBrainsMono, size: 19, weight: .bold)!]))
        text.append(NSAttributedString(string: " Code", attributes: [.font: Font.monospace(19)]))
        let bounds = text.boundingRect(with: CGSize(width: 280, height: 200), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        XCTAssertTrue(bounds.width.isFinite && bounds.height > 0 && bounds.height < 200)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 160)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
            text.draw(in: CGRect(x: 20, y: 20, width: 280, height: 120))
        }
        XCTAssertNotNil(image.pngData())
        let attachment = XCTAttachment(image: image)
        attachment.name = "JetBrains Mono Chinese emoji bold and protected code"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}

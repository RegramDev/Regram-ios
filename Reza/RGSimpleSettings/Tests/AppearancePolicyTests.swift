import Foundation

@main
private enum AppearancePolicyTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() {
        let fileId = String(repeating: "a", count: 64)
        expect(RGFontSelection(id: fileId)?.faceIndex == 0, "Legacy font hashes must keep selecting the first face")
        expect(RGFontSelection(id: RGFontSelection.id(fileId: fileId, faceIndex: 3))?.faceIndex == 3, "TTC selections must retain their face index")
        expect(RGFontSelection(id: fileId + ":3")?.fileId == fileId, "TTC faces must resolve one shared file")
        for invalid in ["../font", fileId + ":-1", fileId + ":0", fileId + ":01", fileId + ":", fileId + ":1:2", String(repeating: "g", count: 64)] {
            expect(RGFontSelection(id: invalid) == nil, "Invalid font selections must not resolve a file: \(invalid)")
        }
        expect(RGTabBarLayoutPolicy.migratedPercent(legacyWide: true) == 100, "A saved wide bar must remain wide")
        expect(RGTabBarLayoutPolicy.migratedPercent(legacyWide: false) == 0, "A default bar keeps automatic sizing")
        expect(RGTabBarLayoutPolicy.normalizedPercent(-100) == 0, "Invalid old values must be safe")
        expect(RGTabBarLayoutPolicy.normalizedPercent(1) == 50 && RGTabBarLayoutPolicy.normalizedPercent(200) == 100, "Manual sizing must stay in the supported range")
        for container in [120.0, 280.0, 320.0, 390.0, 768.0, 1024.0] {
            for count in 1...4 {
                var previous = 0.0
                for percent in 50...100 {
                    let width = RGTabBarLayoutPolicy.width(containerWidth: container, itemCount: count, percent: Int32(percent))
                    expect(width <= min(500.0, container) && width >= previous, "Sizing must stay inside the viewport and grow monotonically")
                    let widths = RGTabBarLayoutPolicy.itemWidths(availableWidth: width - 8.0, naturalWidths: (0..<count).map { $0 == 0 ? 200.0 : 20.0 })
                    expect(abs(widths.reduce(0, +) - (width - 8.0)) < 0.000001, "Long labels must not spill outside the bar")
                    if width - 8.0 >= Double(count) * 44.0 { expect(widths.allSatisfy { $0 >= 44.0 }, "Each available tap target must be at least 44 pt") }
                    expect(widths.allSatisfy { $0.isFinite && $0 >= 0 }, "Small screens must have valid frames")
                    previous = width
                }
                let full = RGTabBarLayoutPolicy.width(containerWidth: container, itemCount: count, percent: 100)
                expect(full == min(500.0, container), "100% must use all supported width regardless of removed search controls")
                let automatic = RGTabBarLayoutPolicy.width(containerWidth: container, itemCount: count, percent: 0)
                let withSearch = RGTabBarLayoutPolicy.width(containerWidth: container, itemCount: count, percent: 0, searchButtonWidth: 64)
                expect(withSearch >= automatic && withSearch <= full, "An actual search button must reserve space without exceeding the viewport")
            }
        }
        expect(RGTabBarLayoutPolicy.width(containerWidth: .nan, itemCount: 2, percent: 50) == 0, "Invalid viewport dimensions must not create NaN frames")
        expect(RGTabBarLayoutPolicy.itemWidths(availableWidth: 100, naturalWidths: [.infinity, .nan]).allSatisfy { $0 == 50 }, "Invalid measurements must fall back safely")
        for family in RGFontFamily.allCases {
            for messages in [false, true] {
                for interface in [false, true] {
                    let config = RGFontConfiguration(family: family.rawValue, messages: messages, interface: interface)
                    expect(config.family(for: .messages) == (messages ? family : .system), "Chat scope must be independent")
                    expect(config.family(for: .interface) == (interface ? family : .system), "Interface scope must be independent")
                    expect(config.family(for: .system) == .system, "Emoji and other protected system content must never be overridden")
                }
            }
        }
        expect(RGFontConfiguration(family: "unknown-font", messages: true, interface: true).family == .system, "Unknown persisted fonts must use system defaults")
        let english = RGFontConfiguration(family: "jetBrainsMono", messages: true, interface: false, chineseFamily: "ibmPlexSansSC")
        let serifChinese = RGFontConfiguration(family: "jetBrainsMono", messages: true, interface: false, chineseFamily: "notoSerifSC")
        expect(english.chineseFamily(for: .messages) == .ibmPlexSansSC && english.chineseFamily(for: .interface) == .system, "Chinese must respect application areas independently of Latin")
        expect(english.cacheKey(for: .messages) != serifChinese.cacheKey(for: .messages), "Changing only Chinese must invalidate font caches")
        expect(english.cacheKey(for: .system) == serifChinese.cacheKey(for: .system), "Protected fonts must be independent of both selections")
        let chineseOnly = RGFontConfiguration(family: "system", messages: true, interface: true, chineseFamily: "notoSerifSC")
        expect(chineseOnly.usesCustomFonts(for: .messages), "Chinese-only selection must apply while English remains native")
        let legacyChinese = RGFontConfiguration.migratedChoices(legacyFamily: "ibmPlexSansSC")
        expect(legacyChinese.latin == .system && legacyChinese.chinese == .ibmPlexSansSC, "Old Chinese choice must migrate to the Chinese selector")
        let legacyEnglish = RGFontConfiguration.migratedChoices(legacyFamily: "lora")
        expect(legacyEnglish.latin == .lora && legacyEnglish.chinese == .system, "Old English choice must be retained")
        expect(RGFontConfiguration(family: "inter", messages: true, interface: true, chineseFamily: "unknown").chineseFamily == .system, "Unknown Chinese choices must fall back safely")
        expect(!RGFontFamily.latinChoices.contains(.ibmPlexSansSC), "Chinese faces belong in their own selector")
        print("Appearance policy regression checks passed")
    }
}

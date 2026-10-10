import Foundation

// Only the bundle access adapter is replaced. Lookup uses the application's real strings files.
extension String {
    func i18n(_ language: String) -> String {
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(language).lproj/SGLocalizable.strings")
        let values = NSDictionary(contentsOf: url) as? [String: String] ?? [:]
        return values[self] ?? self
    }
}

@main enum SettingsSearchTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            for word in ["TTF", "otf", " TTC ", "JetBrains", "Anthropic", "Google", "字体", "字體", "字型", "中文"] {
                expect(RGProSearchIndex.matches(query: word, id: "fonts", lang: language), "Font import and script aliases must lead to Fonts")
            }
            expect(RGProSearchIndex.matches(query: "online", id: "ghostMode", lang: language), "Nested online-presence setting must be discoverable")
            expect(RGProSearchIndex.matches(query: "regex", id: "messageFilter", lang: language), "Nested regex setting must be discoverable")
            expect(RGProSearchIndex.matches(query: "google 字体", id: "fonts", lang: language), "Multi-word queries must match one destination")
            expect(RGProSearchIndex.hasMatches(query: "赞助", lang: language), "Sponsored-ad control must be searchable")
            expect(RGProSearchIndex.matches(query: "reset", id: "eraseAllData", lang: language), "Reset alias must identify the actual data-clear action")
            expect(!RGProSearchIndex.hasMatches(query: "   ", lang: language), "Whitespace must not create a cross-page search result")
            expect(!RGProSearchIndex.hasMatches(query: "unknown setting xyz", lang: language), "Unmatched queries must not show misleading destinations")
        }
        print("Settings search checks passed: real localizations, fonts/formats, nested privacy controls, multi-word queries, whitespace and no matches")
    }
}

import Foundation

extension String {
    func i18n(_ language: String) -> String {
        let path = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(language + ".lproj/RGLocalizable.strings")
        return (NSDictionary(contentsOf: path) as? [String: String])?[self] ?? self
    }
}
@main struct SettingsCatalogTests {
    static func main() {
        assert(Set(RGSettingsCatalog.entries.map(\.id)).count == RGSettingsCatalog.entries.count)
        for language in ["en", "zh-hans", "zh-hant"] {
            for entry in RGSettingsCatalog.entries {
                assert(entry.titleKey.i18n(language) != entry.titleKey, "Missing title: \(entry.titleKey) / \(language)")
                assert(entry.pageTitleKey.i18n(language) != entry.pageTitleKey, "Missing page title: \(entry.pageTitleKey)")
                let restored = RGSettingsDestination.parse(entry.destination.url, appSpecificScheme: "fixture-app")
                assert(restored == entry.destination, "Every search result must round-trip through its copied URL")
            }
        }
        func contains(_ query: String, _ page: String, _ item: String) -> Bool {
            RGSettingsCatalog.results(query: query, language: "zh-hans").contains { $0.destination.page == page && $0.destination.item == item }
        }
        assert(contains("本地会员", "pro.tools", "localPremium"))
        assert(contains("温度", "llm", "temperature"))
        assert(contains("OpenAI 模型", "llm", "model"))
        assert(RGSettingsCatalog.results(query: "温度", language: "zh-hans").allSatisfy { $0.destination.item == "temperature" })
        assert(contains("复读", "settings.messageActions", "messageDoubleTapAction"))
        assert(contains("照片 上传", "settings.photos", "outgoingPhotoQuality"))
        assert(contains("分隔线", "settings.chatList", "hideChatListSeparators"))
        assert(RGSettingsCatalog.results(query: "检查更新", language: "zh-hans").isEmpty)
        assert(RGSettingsDestination.parse(URL(string: "tg://rg/settings?page=updates")!, appSpecificScheme: "fixture-app") == nil)
        assert(contains("DC1", "datacenters", "start"))
        assert(RGSettingsCatalog.results(query: "书签", language: "zh-hans").isEmpty, "Bookmarks belong on outer Settings, not the Pro catalog")
        assert(contains("总结", "pro.messages", "summarySettings"))
        assert(contains("DoH", "networkPolicy", "enabled"))
        assert(RGSettingsCatalog.results(query: "色调", language: "zh-hans").isEmpty)
        assert(RGSettingsDestination(page: "settings.appearance", item: "liquidGlassTintPercent") == RGSettingsDestination(page: "bottomBar"))
        assert(contains("DNS", "networkPolicy", "test"))
        assert(contains("总结", "summary", "enabled"))
        assert(contains("盘古", "pro.input", "panguSpacing"))
        assert(contains("上传", "settings.transfer", "uploadSpeedBoost"))
        assert(RGSettingsDestination(page: "pro.messages", item: "panguSpacing") == RGSettingsDestination(page: "pro.input", item: "panguSpacing"))
        assert(RGSettingsDestination(page: "settings.app", item: "enableVoipTcp") == RGSettingsDestination(page: "settings.transfer", item: "enableVoipTcp"))
        assert(RGSettingsDestination(page: "diagnostics", item: "datacenters") == RGSettingsDestination(page: "datacenters", item: "start"))
        assert(contains("字体", "fonts", "latin"))
        assert(RGSettingsCatalog.results(query: "灵动岛", language: "zh-hans").isEmpty)
        assert(RGSettingsCatalog.results(query: "   ", language: "en").isEmpty)
        assert(RGSettingsCatalog.results(query: "unrecognized setting xyz", language: "en").isEmpty)
        for url in ["https://rg/settings?page=pro.privacy", "tg://user:secret@rg/settings?page=llm", "tg://rg/settings?page=llm&page=updates", "tg://rg/settings?page=unknown", "tg://rg/settings?page=llm&item=../apiKey", "tg://rg/settings?page=llm&apiKey=secret", "tg://rg/settings?page=llm#value", "tg://rg/settings?page=llm&item="] {
            assert(RGSettingsDestination.parse(URL(string: url)!, appSpecificScheme: "fixture-app") == nil, url)
        }
        for url in ["tg://sg/settings?page=llm&item=model", "RG://settings?page=llm&item=model", "fixture-app://rg/settings?page=llm&item=model"] {
            assert(RGSettingsDestination.parse(URL(string: url)!, appSpecificScheme: "fixture-app") == RGSettingsDestination(page: "llm", item: "model"))
        }
        print("Settings catalog checks passed: global leaf search, locale coverage, stable unique destinations, URL round-trips and invalid links")
    }
}

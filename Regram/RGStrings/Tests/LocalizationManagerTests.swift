import Foundation
final class RGLogger { static let shared = RGLogger(); func log(_ tag: String, _ message: String) {} }
func getAppBundle() -> Bundle { Bundle(path: CommandLine.arguments[1])! }

@main struct LocalizationManagerTests {
    static func main() {
        for locale in ["zh-hans", "ZH_Hans", "zh-CN", "zh-SG", "zh-hans-raw"] {
            assert("Settings.ProCategory.media".i18n(locale) == "媒体与链接", locale)
        }
        for locale in ["zh-hant", "ZH_Hant", "zh-TW", "zh-HK"] {
            assert("Settings.ProCategory.media".i18n(locale) == "媒體與連結", locale)
        }
        assert("Settings.ProCategory.media".i18n("en-US") == "Media & Links")
        assert("Fixture.Format".i18n("en", args: "42", 7) == "42 / 7")
        assert(i18n("Fixture.Format", "en", "label", 9) == "label / 9")
        assert(RGLocalizationManager.shared.preferredLocale(primary: "zh-CN", secondary: "en") == "zh-hans")
        assert(RGLocalizationManager.shared.preferredLocale(primary: "ZH_TW", secondary: "en") == "zh-hant")
        assert(RGLocalizationManager.shared.preferredLocale(primary: "unsupported-custom", secondary: "en") == "en")
        assert("RG.BottomBarLayout.Footer".i18n("en").contains("100%"))
        assert("Settings.CustomColors.Saturation.Notice".i18n("en").contains("0%"))
        print("Localization checks passed: selected language, normalized regions, variadic formatting and literal percentages")
    }
}

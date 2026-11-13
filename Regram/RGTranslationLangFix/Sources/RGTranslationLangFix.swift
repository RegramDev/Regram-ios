import Foundation

// MARK: Regram — identify the script used by language packs and language recognizers.
public func rgChineseTranslationScript(_ code: String) -> String? {
    let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
    let parts = normalized.split(separator: "-")
    if parts.first == "zhcncc" || normalized == "regram-zh-hans" || normalized == "regram-zh-hans-raw" {
        return "zh-hans"
    }
    if parts.first == "taiwan" || parts.first == "hongkong" { return "zh-hant" }
    guard parts.first == "zh" else { return nil }
    if parts.contains("hans") { return "zh-hans" }
    if parts.contains("hant") { return "zh-hant" }
    if parts.contains("cn") || parts.contains("sg") { return "zh-hans" }
    if parts.contains("tw") || parts.contains("hk") || parts.contains("mo") { return "zh-hant" }
    return nil
}

public func rgTranslationLangFix(_ language: String) -> String {
    if language.hasPrefix("de-") {
        return "de"
    } else if language.hasPrefix("zh-") && rgChineseTranslationScript(language) != "zh-hant" {
        return "zh"
    } else {
        return language
    }
}

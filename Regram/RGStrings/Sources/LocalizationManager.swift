import Foundation

import RGLogging
import AppBundle


public let RGFallbackLocale = "en"

public class RGLocalizationManager {
    
    public static let shared = RGLocalizationManager()
    
    private let appBundle: Bundle
    private var localizations: [String: [String: String]] = [:]
    private var webLocalizations: [String: [String: String]] = [:]
    private let fallbackMappings: [String: String] = [
        // "from": "to"
        "zh-hant": "zh-hans",
        "be": "ru",
        "nb": "no",
        "ckb": "ku",
        "sdh": "ku"
    ]
    
    private init(fetchLocale: String = RGFallbackLocale) {
        self.appBundle = getAppBundle()
        // Iterating over all the app languages and loading RGLocalizable.strings
        self.appBundle.localizations.forEach { locale in
            if locale != "Base" {
                localizations[locale] = loadLocalDictionary(for: locale)
            }
        }
        // Downloading one specific locale
        self.downloadLocale(fetchLocale)
    }
    
    public func localizedString(_ key: String, _ locale: String = RGFallbackLocale, args: CVarArg...) -> String {
        return self.localizedString(key, locale, arguments: args)
    }

    public func localizedString(_ key: String, _ locale: String, arguments: [CVarArg]) -> String {
        let sanitizedLocale = self.sanitizeLocale(locale)
        if let localizedString = findLocalizedString(forKey: key, inLocale: sanitizedLocale) {
            if arguments.isEmpty {
                return localizedString.replacingOccurrences(of: "%%", with: "%")
            } else {
                return String(format: localizedString, locale: Locale(identifier: sanitizedLocale), arguments: arguments)
            }
        }
        
        RGLogger.shared.log("Strings", "Missing string for key: \(key) in locale: \(locale)")
        return key
    }
    
    private func loadLocalDictionary(for locale: String) -> [String: String] {
        guard let path = self.appBundle.path(forResource: "RGLocalizable", ofType: "strings", inDirectory: nil, forLocalization: locale) else {
            // RGLogger.shared.log("Localization", "Unable to find path for locale: \(locale)")
            return [:]
        }

        guard let dictionary = NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String] else {
            // RGLogger.shared.log("Localization", "Unable to load dictionary for locale: \(locale)")
            return [:]
        }

        return dictionary
    }
    
    public func downloadLocale(_ locale: String) {
        #if DEBUG
        RGLogger.shared.log("Strings", "DEBUG ignoring locale download: \(locale)")
        if ({ return true }()) {
            return
        }
        #endif
        let sanitizedLocale = self.sanitizeLocale(locale)
        guard let url = URL(string: self.getStringsUrl(for: sanitizedLocale)) else {
            RGLogger.shared.log("Strings", "Invalid URL for locale: \(sanitizedLocale)")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            if let localeDict = NSDictionary(contentsOf: url) as? [String: String] {
                DispatchQueue.main.async {
                    self.webLocalizations[sanitizedLocale] = localeDict
                    RGLogger.shared.log("Strings", "Successfully downloaded locale \(sanitizedLocale)")
                }
            } else {
                RGLogger.shared.log("Strings", "Failed to download \(sanitizedLocale)")
            }
        }
    }
    
    public func preferredLocale(primary: String, secondary: String?) -> String {
        let normalized = sanitizeLocale(primary)
        if localizations[normalized] != nil { return normalized }
        return secondary.map(sanitizeLocale) ?? RGFallbackLocale
    }

    private func sanitizeLocale(_ locale: String) -> String {
        var value = locale.lowercased().replacingOccurrences(of: "_", with: "-")
        if value.hasSuffix("-raw") { value = String(value.dropLast(4)) }
        if value == "zh" || value.hasPrefix("zh-cn") || value.hasPrefix("zh-sg") || value.hasPrefix("zh-hans") { return "zh-hans" }
        if value.hasPrefix("zh-tw") || value.hasPrefix("zh-hk") || value.hasPrefix("zh-mo") || value.hasPrefix("zh-hant") { return "zh-hant" }
        if value == "nb" { return "no" }
        if value.hasPrefix("pt-") { return "pt" }
        if localizations[value] != nil { return value }
        return value.split(separator: "-").first.map(String.init) ?? RGFallbackLocale
    }

    private func findLocalizedString(forKey key: String, inLocale locale: String) -> String? {
        if let string = self.localizations[locale]?[key], !string.isEmpty {
            return string
        }
        if let string = self.webLocalizations[locale]?[key], !string.isEmpty {
            return string
        }
        if let fallbackLocale = self.fallbackMappings[locale] {
            return self.findLocalizedString(forKey: key, inLocale: fallbackLocale)
        }
        return self.localizations[RGFallbackLocale]?[key]
    }

    private func getStringsUrl(for locale: String) -> String {
        return "https://raw.githubusercontent.com/RegramDev/Regram-ios/master/Regram/RGStrings/Strings/\(locale).lproj/RGLocalizable.strings"
    }

}

public func i18n(_ key: String, _ locale: String = RGFallbackLocale, _ args: CVarArg...) -> String {
    RGLocalizationManager.shared.localizedString(key, locale, arguments: args)
}


public extension String {
    func i18n(_ locale: String = RGFallbackLocale, args: CVarArg...) -> String {
        return RGLocalizationManager.shared.localizedString(self, locale, arguments: args)
    }
}

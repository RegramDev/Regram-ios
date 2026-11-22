// MARK: Regram — share the existing localization and formatting behavior with feature components.
import Foundation
public func rgFeatureI18n(_ key: String, _ language: String = "en", args: String...) -> String {
    let value = key.i18n(language)
    return args.isEmpty ? value : String(format: value, arguments: args)
}
public final class RGFeatureLocalization {
    public static let shared = RGFeatureLocalization()
    public func localizedString(_ key: String, _ language: String = "en", args: String...) -> String {
        let value = key.i18n(language)
        return args.isEmpty ? value : String(format: value, arguments: args)
    }
}

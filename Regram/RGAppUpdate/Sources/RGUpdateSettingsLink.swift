// MARK: Regram — use the configured application protocol, never a web or wallet protocol.
import Foundation
import BuildConfig

enum RGUpdateSettingsLink {
    static func url(appSpecificScheme: String, registeredSchemes: [String]) -> URL {
        let reserved: Set<String> = ["tonsite", "ton", "tc", "http", "https", "file", "telegram"]
        let lower = appSpecificScheme.lowercased()
        let valid = appSpecificScheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil
        let scheme = valid && !reserved.contains(lower) && registeredSchemes.contains(where: { $0.lowercased() == lower }) ? appSpecificScheme : "tg"
        var components = URLComponents()
        components.scheme = scheme; components.host = "rg"; components.path = "/settings"
        components.queryItems = [URLQueryItem(name: "page", value: "updates")]
        return components.url!
    }

    static var current: URL {
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        let config = BuildConfig(baseAppBundleId: Bundle.main.bundleIdentifier ?? "")
        return url(appSpecificScheme: config.appSpecificUrlScheme, registeredSchemes: schemes)
    }
}

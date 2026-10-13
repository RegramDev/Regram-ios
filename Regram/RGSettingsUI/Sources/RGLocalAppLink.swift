// MARK: Regram — resolve local settings links before Telegram's query-based URLs.
import Foundation

public func rgLocalAppLinkPath(_ url: URL, appSpecificScheme: String) -> String? {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
          url.user == nil, url.password == nil, url.port == nil else { return nil }
    let localSchemes = ["rg", "regram", "sg"]
    guard scheme == "tg" || localSchemes.contains(scheme) || scheme == appSpecificScheme.lowercased() else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    let route: String
    if localSchemes.contains(host), parts.count == 1 {
        route = parts[0].lowercased()
    } else if localSchemes.contains(scheme), parts.isEmpty {
        route = host
    } else { return nil }
    switch route {
    case "debug", "settings", "ios_settings", "contacts", "restart": return route
    case "rgdebug", "rg_debug", "sgdebug", "sg_debug": return "rgdebug"
    case "pro", "premium", "buy", "restore_purchases", "pro_restore", "validate", "restore": return "pro"
    default: return nil
    }
}

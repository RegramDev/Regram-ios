// MARK: Regram — resolve local settings links before Telegram's query-based URLs.
import Foundation

public func rgLocalAppLinkPath(_ url: URL, appSpecificScheme: String) -> String? {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
          url.user == nil, url.password == nil, url.port == nil else { return nil }
    let localSchemes = ["rg", "regram"]
    guard scheme == "tg" || localSchemes.contains(scheme) || (scheme != "sg" && scheme == appSpecificScheme.lowercased()) else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    let route: String
    if localSchemes.contains(host), parts.count == 1 {
        route = parts[0].lowercased()
    } else if localSchemes.contains(scheme), parts.isEmpty {
        route = host
    } else { return nil }
    switch route {
    case "debug", "settings", "ios_settings", "contacts", "restart": return route
    case "rgdebug", "rg_debug": return "rgdebug"
    case "pro": return "pro"
    default: return nil
    }
}

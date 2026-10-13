// MARK: Regram — stable local settings addresses; never include saved values or account identities.
import Foundation

public struct RGSettingsDestination: Hashable {
    public let page: String
    public let item: String?
    public static let pages: Set<String> = [
        "pro.home", "pro.messages", "pro.privacy", "pro.translation", "pro.media", "pro.appearance", "pro.notifications", "pro.tools",
        "settings.appearance", "settings.folders", "settings.chatList", "settings.profiles", "settings.stories", "settings.translation", "settings.messageActions", "settings.media", "settings.photos", "settings.stickers", "settings.recording", "settings.app",
        "bottomBar", "llm", "stt", "updates", "linkPreview", "antiFeatures", "ghostMode", "fonts", "backup", "diagnostics", "chatPreferences", "messageFilter", "hiddenUsers", "antiRevokeChats", "revokedMessages", "appIcons", "appBadges", "contextMenu"
    ]
    public init?(page: String, item: String? = nil) {
        guard Self.pages.contains(page), item.map(Self.validItem) ?? true else { return nil }
        self.page = page; self.item = item
    }
    private static func validItem(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 96 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }
    }
    public var url: URL {
        var components = URLComponents()
        components.scheme = "tg"; components.host = "rg"; components.path = "/settings"
        components.queryItems = [URLQueryItem(name: "page", value: page)] + (item.map { [URLQueryItem(name: "item", value: $0)] } ?? [])
        return components.url!
    }
    public static func parse(_ url: URL, appSpecificScheme: String) -> RGSettingsDestination? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.user == nil, components.password == nil, components.port == nil, components.fragment == nil else { return nil }
        let scheme = components.scheme?.lowercased() ?? "", host = components.host?.lowercased() ?? ""
        let aliases = ["rg", "regram", "sg"]
        let supported = scheme == "tg" || aliases.contains(scheme) || scheme == appSpecificScheme.lowercased()
        guard supported, (aliases.contains(host) && components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "settings") || (aliases.contains(scheme) && host == "settings" && components.path.isEmpty) else { return nil }
        let query = components.queryItems ?? []
        guard query.allSatisfy({ ["page", "item"].contains($0.name) && $0.value != nil }), Set(query.map(\.name)).count == query.count,
              let page = query.first(where: { $0.name == "page" })?.value else { return nil }
        return Self(page: page, item: query.first(where: { $0.name == "item" })?.value)
    }
}

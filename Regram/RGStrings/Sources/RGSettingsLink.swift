// MARK: Regram — stable local settings addresses; never include saved values or account identities.
import Foundation

public struct RGSettingsDestination: Hashable {
    public let page: String
    public let item: String?
    public static let pages: Set<String> = [
        "pro.home", "pro.messages", "pro.input", "pro.privacy", "pro.translation", "pro.media", "pro.appearance", "pro.notifications", "pro.network", "pro.tools",
        "settings.appearance", "settings.folders", "settings.chatList", "settings.profiles", "settings.stories", "settings.translation", "settings.messageActions", "settings.media", "settings.photos", "settings.stickers", "settings.recording", "settings.app",
        "settings.input", "settings.transfer", "settings.privacy",
        "bottomBar", "llm", "stt", "linkPreview", "antiFeatures", "ghostMode", "fonts", "backup", "diagnostics", "datacenters", "bookmarks", "chatPreferences", "messageFilter", "hiddenUsers", "antiRevokeChats", "revokedMessages", "appIcons", "appBadges", "contextMenu"
    ]
    public init?(page: String, item: String? = nil) {
        guard Self.pages.contains(page), item.map(Self.validItem) ?? true else { return nil }
        // MARK: Regram — old copied links follow moved controls without another visible entry.
        if page == "diagnostics", item == "datacenters" { self.page = "datacenters"; self.item = "start"; return }
        let moves: [String: String] = [
            "pro.messages:inputToolbar": "pro.input", "pro.messages:mentionAsUserIdLink": "pro.input", "pro.messages:panguSpacing": "pro.input", "pro.messages:defaultOutgoingFormatting": "pro.input", "pro.messages:chatPreferences": "pro.input",
            "pro.privacy:localPremium": "pro.tools", "pro.tools:diagnostics": "pro.network",
            "settings.messageActions:hideRecordingButton": "settings.input", "settings.messageActions:disableSendAsButton": "settings.input", "settings.messageActions:sendWithReturnKey": "settings.input",
            "settings.media:uploadSpeedBoost": "settings.transfer", "settings.media:downloadSpeedBoost": "settings.transfer", "settings.app:enableVoipTcp": "settings.transfer",
            "settings.media:disableGalleryCamera": "settings.recording", "settings.media:disableGalleryCameraPreview": "settings.recording",
            "settings.app:hideChannelBottomButton": "settings.messageActions", "settings.app:contentSettings": "settings.privacy", "settings.profiles:hidePhoneInSettings": "settings.privacy"
        ]
        self.page = item.flatMap { moves[page + ":" + $0] } ?? page; self.item = item
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

import Foundation

// MARK: Regram
public enum RGAppIconNames {
    public static let primaryName = "RGConversation"
    public static let alternateName = "RGGathering"
    public static let alternateNames = ["RGAzure", "RGIris", "RGMint", alternateName, "RGAmber", "RGNebula", "RGJade", "RGClassic", "RGXChat"]
    public static let allNames = [primaryName] + alternateNames

    private static let titleNames = [primaryName: "conversation", "RGAzure": "azure", "RGIris": "iris", "RGMint": "mint", alternateName: "gathering", "RGAmber": "amber", "RGNebula": "nebula", "RGJade": "jade", "RGClassic": "classic", "RGXChat": "xchat"]
    public static func titleKey(_ name: String) -> String { "AppIcon.Name." + (titleNames[name] ?? "conversation") }

    /// UIKit represents the primary icon with nil. Retired artwork falls back to it.
    public static func canonicalName(_ name: String?) -> String? {
        name.flatMap { alternateNames.contains($0) ? $0 : nil }
    }

    public static func isRetiredSystemName(_ name: String?) -> Bool {
        guard let name else { return false }
        return !alternateNames.contains(name)
    }

    public static func previewName(_ name: String?) -> String {
        (canonicalName(name) ?? primaryName) + "Preview"
    }
}

public enum RGAppBadgeNames {
    public static let defaultName = "RGConversationBadge"
    public static let alternateName = "RGGatheringBadge"
    public static let allNames = [defaultName, "RGAzureBadge", "RGIrisBadge", "RGMintBadge", alternateName, "RGAmberBadge", "RGNebulaBadge", "RGJadeBadge", "RegramAppBadge", "ZhiqiuAppBadge"]

    /// Empty preferences, removed artwork and old backups all resolve to current artwork.
    public static func canonicalName(_ name: String) -> String {
        allNames.contains(name) ? name : defaultName
    }
}

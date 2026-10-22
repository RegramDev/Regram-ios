import Foundation

// MARK: Regram
public enum RGAppIconNames {
    public static let primaryName = "RGConversation"
    public static let alternateName = "RGGathering"

    /// UIKit represents the primary icon with nil. Retired artwork falls back to it.
    public static func canonicalName(_ name: String?) -> String? {
        name == alternateName ? alternateName : nil
    }

    public static func isRetiredSystemName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name != alternateName
    }

    public static func previewName(_ name: String?) -> String {
        (canonicalName(name) ?? primaryName) + "Preview"
    }
}

public enum RGAppBadgeNames {
    public static let defaultName = "RGConversationBadge"
    public static let alternateName = "RGGatheringBadge"

    /// Empty preferences, removed artwork and old backups all resolve to current artwork.
    public static func canonicalName(_ name: String) -> String {
        name == alternateName ? alternateName : defaultName
    }
}

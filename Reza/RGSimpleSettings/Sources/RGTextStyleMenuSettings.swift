// MARK: Regram — adapted from NextAlone/Nagram-iOS (fa29656a2427); original contributors retain copyright.
import Foundation

/// Text styles that can be flattened onto the first level of the composer's selection menu.
public enum RGFeatureTextStyleMenuItemId: String, CaseIterable {
    case quote
    case spoiler
    case bold
    case italic
    case monospace
    case link
    case date
    case strikethrough
    case underline
    case code
}

/// Where the flattened styles go in the selection menu. The full Format submenu keeps its own place,
/// right after the system Cut/Copy/Paste group.
public enum RGFeatureTextStyleMenuPosition: String, CaseIterable {
    case first
    case beforeFormat
    case afterFormat
    case last
}

private let rgFeatureTextStyleMenuOrderKey = "features.textStyleMenu.order"
private let rgFeatureTextStyleMenuEnabledKey = "features.textStyleMenu.enabled"
private let rgFeatureTextStyleMenuPositionKey = "features.textStyleMenu.position"

public extension RGSimpleSettings {
    var textStyleMenuItemOrder: [RGFeatureTextStyleMenuItemId] {
        get {
            return self.normalizedTextStyleMenuOrder(self.textStyleMenuIds(from: UserDefaults.standard.string(forKey: rgFeatureTextStyleMenuOrderKey)))
        }
        set {
            let order = self.normalizedTextStyleMenuOrder(newValue)
            RGFeaturePreferences.shared.set(order.map(\.rawValue).joined(separator: ","), forKey: rgFeatureTextStyleMenuOrderKey)
        }
    }

    /// Nothing is flattened until the user picks styles, so the menu is unchanged by default.
    func isTextStyleMenuItemEnabled(_ id: RGFeatureTextStyleMenuItemId) -> Bool {
        return self.enabledTextStyleMenuItemIds.contains(id)
    }

    func setTextStyleMenuItemEnabled(_ id: RGFeatureTextStyleMenuItemId, enabled: Bool) {
        var ids = self.enabledTextStyleMenuItemIds
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        RGFeaturePreferences.shared.set(ids.map(\.rawValue).sorted().joined(separator: ","), forKey: rgFeatureTextStyleMenuEnabledKey)
    }

    /// The enabled styles in the user's order.
    var enabledTextStyleMenuItems: [RGFeatureTextStyleMenuItemId] {
        let enabled = self.enabledTextStyleMenuItemIds
        return self.textStyleMenuItemOrder.filter { enabled.contains($0) }
    }

    var textStyleMenuPosition: RGFeatureTextStyleMenuPosition {
        get {
            return UserDefaults.standard.string(forKey: rgFeatureTextStyleMenuPositionKey).flatMap(RGFeatureTextStyleMenuPosition.init(rawValue:)) ?? .beforeFormat
        }
        set {
            RGFeaturePreferences.shared.set(newValue.rawValue, forKey: rgFeatureTextStyleMenuPositionKey)
        }
    }

    func resetTextStyleMenu() {
        RGFeaturePreferences.shared.removeObject(forKey: rgFeatureTextStyleMenuOrderKey)
        RGFeaturePreferences.shared.removeObject(forKey: rgFeatureTextStyleMenuEnabledKey)
        RGFeaturePreferences.shared.removeObject(forKey: rgFeatureTextStyleMenuPositionKey)
    }
}

private extension RGSimpleSettings {
    var enabledTextStyleMenuItemIds: Set<RGFeatureTextStyleMenuItemId> {
        return Set(self.textStyleMenuIds(from: UserDefaults.standard.string(forKey: rgFeatureTextStyleMenuEnabledKey)))
    }

    func textStyleMenuIds(from string: String?) -> [RGFeatureTextStyleMenuItemId] {
        guard let string, !string.isEmpty else {
            return []
        }
        return string.split(separator: ",").compactMap { RGFeatureTextStyleMenuItemId(rawValue: String($0)) }
    }

    func normalizedTextStyleMenuOrder(_ ids: [RGFeatureTextStyleMenuItemId]) -> [RGFeatureTextStyleMenuItemId] {
        var result: [RGFeatureTextStyleMenuItemId] = []
        var seen = Set<RGFeatureTextStyleMenuItemId>()
        for id in ids + RGFeatureTextStyleMenuItemId.allCases {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }
}

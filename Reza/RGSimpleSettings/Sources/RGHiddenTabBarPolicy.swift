// MARK: Regram — keep a settings route when the root tabs are hidden.
import Foundation

public enum RGHiddenTabBarPolicy {
    public static func isHidden(transientlyHidden: Bool, isTabBarVisible: Bool) -> Bool {
        transientlyHidden || !isTabBarVisible
    }

    public static func canReturnToChats(isTabBarVisible: Bool, isRootSettings: Bool, isTopController: Bool, editing: Bool, avatarExpanded: Bool) -> Bool {
        !isTabBarVisible && isRootSettings && isTopController && !editing && !avatarExpanded
    }

    public static func completeBackGesture(distance: Double, width: Double, velocity: Double) -> Bool {
        distance > 0 && (distance >= max(48, min(80, width * 0.2)) || velocity >= 500)
    }

    public static func shouldBeginBackGesture(distanceX: Double, distanceY: Double, velocityX: Double, velocityY: Double) -> Bool {
        guard distanceX.isFinite, distanceY.isFinite, velocityX.isFinite, velocityY.isFinite else { return false }
        // Prefer the initial movement over a noisy instantaneous velocity once the pan is established.
        let useDistance = max(abs(distanceX), abs(distanceY)) >= 8
        let x = useDistance ? distanceX : velocityX
        let y = useDistance ? distanceY : velocityY
        return x > 0 && x > abs(y) * 1.25
    }

    public static func showSettings(isTabBarVisible: Bool, isRootChatList: Bool, editing: Bool, reordering: Bool) -> Bool {
        !isTabBarVisible && isRootChatList && !editing && !reordering
    }
}

// MARK: Regram — a glass bar restored after search needs a fresh effect hierarchy.
public struct RGTabBarPresentationState {
    public let hasItems: Bool
    public let hasContent: Bool
    public let isVisible: Bool

    public init(hasItems: Bool, hasContent: Bool, isHidden: Bool, hasToolbar: Bool) {
        self.hasItems = hasItems
        self.hasContent = hasContent
        self.isVisible = hasContent && !isHidden && !hasToolbar
    }

    public func requiresFreshGlass(after previous: RGTabBarPresentationState?) -> Bool {
        guard let previous else { return false }
        return (!previous.hasItems && self.hasItems)
            || (!previous.hasContent && self.hasContent)
            || (!previous.isVisible && self.isVisible)
    }
}

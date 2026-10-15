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

    public static func showSettings(isTabBarVisible: Bool, isRootChatList: Bool, editing: Bool, reordering: Bool) -> Bool {
        !isTabBarVisible && isRootChatList && !editing && !reordering
    }
}

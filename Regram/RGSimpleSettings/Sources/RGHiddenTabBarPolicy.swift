// MARK: Regram — keep a settings route when the root tabs are hidden.
import Foundation

public enum RGHiddenTabBarPolicy {
    public static func showSettings(isTabBarVisible: Bool, isRootChatList: Bool, editing: Bool, reordering: Bool) -> Bool {
        !isTabBarVisible && isRootChatList && !editing && !reordering
    }
}

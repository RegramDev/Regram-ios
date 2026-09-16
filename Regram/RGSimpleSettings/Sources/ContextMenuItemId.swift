// MARK: Regram
import Foundation

/// The message-menu items Regram lets the user place and order.
///
/// Every one of these can be toggled between the main long-press menu and the "Regram" submenu, and
/// the whole set can be dragged into an arbitrary order. The context menu is emitted by walking
/// `RGSimpleSettings.shared.contextMenuOrder`, so an item missing from this enum is simply not
/// user-manageable — it keeps whatever position upstream gave it.
///
/// `allCases` order is the canonical default, used both for a fresh install and to append items
/// added by a later build onto the end of an order stored by an earlier one. Raw values are
/// persisted, so **do not rename them**; the display name lives in the strings file instead.
public enum RGContextMenuItemId: String, CaseIterable, Hashable {
    /// 复读 — forward straight back into this chat, attribution intact.
    case repeatForward
    /// 无引用复读 — re-send the content here as your own message.
    case repeatCopy
    /// 无引用转发 — pick a chat, forward into it with the sender's name hidden.
    case forwardNoQuote
    case saveToCloud
    case reply
    case selectFromUser
    case saveMedia
    case messageReplies
    case pin
    case restrict
    case report
    case json
}

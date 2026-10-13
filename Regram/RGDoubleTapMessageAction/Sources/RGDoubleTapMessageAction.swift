import Foundation
import RGSimpleSettings
import Postbox
import TelegramCore

// MARK: Regram — double tap on a message (RGSimpleSettings.MessageDoubleTapActionV2).
//
// The item nodes only know how to react and how to open the menu on themselves; every other action
// needs the chat controller, so it is handed back through `perform`.
func rgHandleDoubleTapMessageAction(message: Message, canEditMessage: Bool, sendReaction: () -> Void, showReactions: () -> Void, perform: (RGSimpleSettings.MessageDoubleTapActionV2) -> Void) {
    let action = RGSimpleSettings.shared.resolvedMessageDoubleTapAction(canEditMessage: canEditMessage)
    switch action {
    case .disabled:
        break
    case .sendReaction:
        sendReaction()
    case .showReactions:
        showReactions()
    case .reply, .repeatMessage, .repeatWithoutQuote, .translate, .edit:
        perform(action)
    }
}

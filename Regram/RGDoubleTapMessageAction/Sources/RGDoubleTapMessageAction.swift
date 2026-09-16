import Foundation
import RGSimpleSettings
import Postbox
import TelegramCore


func rgDoubleTapMessageAction(incoming: Bool, message: Message) -> String {
    if incoming {
        return RGSimpleSettings.MessageDoubleTapAction.default.rawValue
    } else {
        return RGSimpleSettings.shared.messageDoubleTapActionOutgoing
    }
}

func rgHandleDoubleTapMessageAction(incoming: Bool, message: Message, editAction: () -> Void, defaultAction: () -> Void) {
    switch rgDoubleTapMessageAction(incoming: incoming, message: message) {
    case RGSimpleSettings.MessageDoubleTapAction.none.rawValue:
        break
    case RGSimpleSettings.MessageDoubleTapAction.edit.rawValue:
        editAction()
    default:
        defaultAction()
    }
}

import Foundation
import Postbox
import RGSimpleSettings

// MARK: Regram — local message attributes across a server rewrite.
//
// An edit (ours, confirmed in RequestEditMessage, or anyone's, replayed as `.EditMessage`) replaces
// the stored message with the server's copy. With "Save edit history" on, the text being replaced is
// appended to the history here, where both versions are at hand. The local attributes would also
// survive through the seed configuration's `mergeMessageAttributes`, which covers every rewrite of
// an existing message, refetches included; carrying them here keeps the updated history in place
// of the stale one.
func rgCarryOverLocalMessageAttributes(previousMessage: Message, updatedText: String, updatedAttributes: [MessageAttribute]) -> [MessageAttribute] {
    var attributes = updatedAttributes.filter { !($0 is RGRevokedMessageAttribute || $0 is RGEditHistoryMessageAttribute) }
    if let revoked = previousMessage.attributes.first(where: { $0 is RGRevokedMessageAttribute }) {
        attributes.append(revoked)
    }
    var editHistory = previousMessage.attributes.first(where: { $0 is RGEditHistoryMessageAttribute }) as? RGEditHistoryMessageAttribute
    if RGSimpleSettings.shared.saveEditHistory, let previousVersion = rgEditHistoryPreviousVersion(previousMessage: previousMessage, updatedText: updatedText, updatedAttributes: updatedAttributes) {
        editHistory = (editHistory ?? RGEditHistoryMessageAttribute(entries: [])).withAppendedEntry(previousVersion)
    }
    if let editHistory {
        attributes.append(editHistory)
    }
    return attributes
}

/// The version an edit replaces, or nil when the text is left alone. The server also re-sends
/// messages for reasons other than an edit (reactions, link previews, views), so a change of
/// formatting alone counts only together with a newer edit date.
private func rgEditHistoryPreviousVersion(previousMessage: Message, updatedText: String, updatedAttributes: [MessageAttribute]) -> RGEditHistoryEntry? {
    let previousEntities = previousMessage.textEntitiesAttribute?.entities ?? []
    let previousEditDate = (previousMessage.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date
    if previousMessage.text == updatedText {
        let updatedEntities = (updatedAttributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
        let updatedEditDate = (updatedAttributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date
        guard previousEntities != updatedEntities, let updatedEditDate, updatedEditDate > (previousEditDate ?? 0) else {
            return nil
        }
    }
    return RGEditHistoryEntry(text: previousMessage.text, entities: previousEntities, date: previousEditDate ?? previousMessage.timestamp)
}

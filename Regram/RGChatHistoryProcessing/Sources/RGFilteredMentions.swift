import Postbox
import SwiftSignalKit
import TelegramCore

// Hidden messages have no visible item to consume their personal-mention tag. Only acknowledge
// messages in the current conversation/topic that the normal read position has already passed.
public func rgFilteredMentionIdsToRead(messages: [Message], peerId: PeerId, threadId: Int64?, readThrough: MessageIndex, isHidden: (Message) -> Bool) -> Set<MessageId> {
    var result = Set<MessageId>()
    for message in messages {
        guard message.id.peerId == peerId, message.id.namespace == Namespaces.Message.Cloud,
              threadId == nil || message.threadId == threadId,
              message.index <= readThrough,
              !message.flags.intersection(.IsIncomingMask).isEmpty,
              message.tags.contains(.unseenPersonalMessage),
              message.attributes.contains(where: { attribute in
                  guard let mention = attribute as? ConsumablePersonalMentionMessageAttribute else { return false }
                  return !mention.consumed && !mention.pending
              }), isHidden(message) else {
            continue
        }
        result.insert(message.id)
    }
    return result
}

/// Explicit @ navigation also handles hidden mentions outside the currently loaded chat window.
/// Exclude each acknowledged id from the next lookup immediately: waiting for the server to clear
/// its tag would otherwise keep returning the same hidden message on a slow or offline connection.
public func rgEarliestVisibleUnseenPersonalMentionMessage(account: Account, peerId: PeerId, threadId: Int64?, isHidden: @escaping (Message) -> Bool) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    func next(ignoring messageIds: Set<MessageId>) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
        return TelegramEngine(account: account).messages.earliestUnseenPersonalMentionMessage(peerId: peerId, threadId: threadId, ignoreMessageIds: messageIds)
        |> mapToSignal { result -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
            guard case let .result(messageId?) = result else {
                return .single(result)
            }
            return account.postbox.transaction { transaction -> Message? in
                return transaction.getMessage(messageId)
            }
            |> mapToSignal { message -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
                guard let message, message.id.peerId == peerId,
                      message.id.namespace == Namespaces.Message.Cloud,
                      threadId == nil || message.threadId == threadId,
                      !message.flags.intersection(.IsIncomingMask).isEmpty,
                      isHidden(message) else {
                    return .single(result)
                }
                account.viewTracker.updateMarkMentionsSeenForMessageIds(messageIds: [messageId])
                return next(ignoring: messageIds.union([messageId]))
            }
        }
    }
    return next(ignoring: [])
}

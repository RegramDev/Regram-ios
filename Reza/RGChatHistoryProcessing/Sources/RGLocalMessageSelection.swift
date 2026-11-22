import Postbox
import SwiftSignalKit
import TelegramCore

/// The existing Select From User action selects at most 500 locally stored, non-service messages.
/// Keep its Postbox query inside Regram rather than reintroducing storage access in TelegramUI.
public func rgLocalMessageIdsForAuthor(account: Account, peerId: EnginePeer.Id, authorId: EnginePeer.Id, threadId: Int64?, limit: Int = 500) -> Signal<[EngineMessage.Id], NoError> {
    return account.postbox.transaction { transaction -> [EngineMessage.Id] in
        var result: [EngineMessage.Id] = []
        transaction.withAllMessages(peerId: peerId, reversed: true, { message in
            guard result.count < limit else { return false }
            guard message.author?.id == authorId else { return true }
            if let threadId, message.threadId != threadId { return true }
            guard !message.media.contains(where: { $0 is TelegramMediaAction }) else { return true }
            result.append(message.id)
            return true
        })
        return result
    }
}

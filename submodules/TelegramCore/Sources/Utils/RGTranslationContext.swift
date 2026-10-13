// MARK: Regram — bounded local context for the opt-in LLM translation backend.
import Foundation
import Postbox
import RGSimpleSettings

func rgTranslationContext(transaction: Transaction, messageId: MessageId) -> [String] {
    guard RGSimpleSettings.shared.translationBackendEnum == .llm,
          RGSimpleSettings.shared.translationLLMUseContext,
          let message = transaction.getMessage(messageId) else { return [] }
    let lowerBound = MessageIndex.lowerBound(peerId: messageId.peerId, namespace: messageId.namespace)
    let earlier: [Message]
    if let threadId = message.threadId {
        earlier = transaction.getMessagesWithThreadId(peerId: messageId.peerId, namespace: messageId.namespace, threadId: threadId, from: message.index, includeFrom: false, to: lowerBound, limit: 20)
    } else {
        earlier = transaction.getMessages(peerId: messageId.peerId, namespace: messageId.namespace, from: message.index, includeFrom: false, to: lowerBound, limit: 20)
    }
    return earlier.filter { previous in
        return !previous.text.isEmpty && !previous.media.contains(where: { $0 is TelegramMediaAction }) && !previous.attributes.contains(where: { $0 is RGRevokedMessageAttribute })
    }.sorted { $0.index < $1.index }.suffix(5).map { String($0.text.prefix(800)) }
}

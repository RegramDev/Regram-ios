import Foundation
import RGSimpleSettings
import Postbox
import TelegramCore
import SwiftSignalKit

// Serial preprocessing consumes immutable Postbox snapshots. Only verdicts and
// in-flight bookkeeping cross back to the UI; node/layout state stays on main.
public final class RGChatHistoryMessageProcessor {
    public static let queue = Queue(name: "regram.chat-history-messages", qos: .userInitiated)
    private struct Eligibility {
        let standalone: Bool
        let grouped: Bool
        let translatedLanguage: String?
    }
    private let accountPeerId: PeerId
    private let cache = RGMessageVerdictCache<MessageId, Eligibility>()
    private let workLock = NSLock()
    private var work = RGTranslationWorkState<MessageId>()

    public init(accountPeerId: PeerId) { self.accountPeerId = accountPeerId }

    private func eligibility(_ message: Message) -> Eligibility {
        if let cached = self.cache.value(for: message.id, version: message.stableVersion) { return cached }
        let base = message.adAttribute == nil && message.id.namespace == Namespaces.Message.Cloud && message.author?.id != self.accountPeerId
        let hasText = !message.text.isEmpty || message.richText != nil
        let hasPoll = message.media.contains { $0 is TelegramMediaPoll }
        let hasTranscription = message.attributes.contains { attribute in
            guard let transcription = attribute as? AudioTranscriptionMessageAttribute else { return false }
            return !transcription.text.isEmpty && !transcription.isPending
        }
        let value = Eligibility(standalone: base && (hasText || hasPoll || hasTranscription), grouped: base && hasText, translatedLanguage: (message.attributes.first { $0 is TranslationMessageAttribute } as? TranslationMessageAttribute)?.toLang)
        self.cache.store(value, for: message.id, version: message.stableVersion)
        return value
    }

    public func prepare(_ messages: [Message]) {
        assert(Self.queue.isCurrent())
        for message in messages { let _ = self.eligibility(message) }
    }

    public func shouldTranslate(_ message: Message, language: String, grouped: Bool) -> Bool {
        let value = self.eligibility(message)
        guard (grouped ? value.grouped : value.standalone), value.translatedLanguage != language else { return false }
        self.workLock.lock()
        defer { self.workLock.unlock() }
        return self.work.canSchedule(message.id, language: language, now: CFAbsoluteTimeGetCurrent())
    }

    public func beginTranslation(_ ids: [MessageId], language: String) -> (generation: UInt64, keys: [MessageId]) {
        self.workLock.lock()
        defer { self.workLock.unlock() }
        return self.work.begin(ids, language: language, now: CFAbsoluteTimeGetCurrent())
    }

    public func finishTranslation(_ ids: [MessageId], language: String, generation: UInt64) {
        self.workLock.lock()
        defer { self.workLock.unlock() }
        self.work.finish(ids, language: language, generation: generation, now: CFAbsoluteTimeGetCurrent())
    }

    public func resetTranslationWork() {
        self.workLock.lock()
        defer { self.workLock.unlock() }
        self.work.reset()
    }
}

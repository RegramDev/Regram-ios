import Foundation
import SwiftSignalKit
import TelegramCore
import RGSimpleSettings

// MARK: Regram
// The single definition of "this message is hidden", shared by the chat history (which drops the
// message from the conversation) and the chat list (which must then preview the previous visible
// message instead). Keeping one predicate is what stops the two surfaces from disagreeing about
// what is hidden.

/// Verdicts already computed, so that re-examining the same window costs a dictionary lookup
/// instead of a fresh scan of every message.
///
/// The chat history is rebuilt on the **main thread** (`ChatHistoryListNode`'s `messageViewQueue` is
/// `Queue.mainQueue()`) on every scroll-driven window change, and each rebuild re-examines every
/// entry it kept. Evaluating a rule means either a case-insensitive `range(of:)` — Unicode folding,
/// not a byte compare — or a regex match, so repeating that per rebuild for a window of hundreds of
/// messages is what made scrolling a filtered chat drop frames.
///
/// A verdict stays valid until either the rules or the message itself change. Rule changes are
/// caught by `RGSimpleSettings.contentFilterGeneration`, which discards the whole table; message
/// changes are caught by Postbox's `stableVersion`, which it increments on every update of a message
/// (`MessageHistoryTable`: `stableVersion = previousMessage.stableVersion + 1`). That makes an edit
/// exact rather than heuristic — comparing text length instead would serve a stale verdict for an
/// edit that happened to preserve it, and a stale *hide* means a message the user never sees.
private final class RGContentFilterVerdictCache {
    static let shared = RGContentFilterVerdictCache()

    private struct Entry {
        let stableVersion: UInt32
        let shouldHide: Bool
    }

    /// Bounded so that a long session cannot grow it without limit. Far above what one rebuild
    /// touches, so the clear below is rare rather than a thrash.
    private let limit = 8192

    private let lock = NSLock()
    private var generation: Int = -1
    private var entries: [EngineMessage.Id: Entry] = [:]

    func verdict(for id: EngineMessage.Id, generation: Int, stableVersion: UInt32) -> Bool? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.generation == generation, let entry = self.entries[id], entry.stableVersion == stableVersion else {
            return nil
        }
        return entry.shouldHide
    }

    func store(_ shouldHide: Bool, for id: EngineMessage.Id, generation: Int, stableVersion: UInt32) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.generation != generation {
            self.generation = generation
            self.entries.removeAll(keepingCapacity: true)
        } else if self.entries.count >= self.limit {
            self.entries.removeAll(keepingCapacity: true)
        }
        self.entries[id] = Entry(stableVersion: stableVersion, shouldHide: shouldHide)
    }
}

public struct RGContentFilterState {
    public let rules: [RGMessageFilterRule]
    public let hiddenSenderIds: Set<Int64>
    /// Chats the keyword rules are switched off in, from the per-chat toggle on a peer's profile.
    /// Hidden senders are deliberately *not* subject to it: hiding someone is about the person, so
    /// it has to hold everywhere they post.
    public let filterDisabledPeerIds: Set<Int64>
    public let accountPeerId: EnginePeer.Id

    /// Generation the verdict cache is keyed on, captured with the rules so that a rule change
    /// landing mid-pass cannot mix verdicts from two rule sets into one table.
    private let generation: Int

    /// Reads the current settings. Decoding the rules and the hidden-sender list is not free, so
    /// build this once per pass rather than per message.
    ///
    /// Reads through the memoised `Set`/`[Rule]` accessors rather than testing the raw `…Raw`
    /// arrays first: those are `@UserDefault` wrappers, so each test was a `UserDefaults` read on
    /// every rebuild, where the decoded values are already cached behind one lock.
    public init(accountPeerId: EnginePeer.Id) {
        let settings = RGSimpleSettings.shared
        let isProUnlocked = settings.ephemeralStatus > 1
        self.rules = isProUnlocked ? settings.messageFilterRules : []
        self.hiddenSenderIds = isProUnlocked ? settings.blockedPeerIds : []
        self.filterDisabledPeerIds = settings.messageFilterDisabledPeerIds
        self.accountPeerId = accountPeerId
        self.generation = settings.contentFilterGeneration
    }

    public var isEmpty: Bool {
        return self.rules.isEmpty && self.hiddenSenderIds.isEmpty
    }

    /// - Parameters:
    ///   - authorId: the sender. Hidden senders are matched on this so a user hidden from their
    ///     profile disappears from every group and comment thread, not just a one-to-one chat.
    ///   - peerId: the conversation, used to apply rules scoped to specific chats.
    ///   - isIncoming: keyword rules only apply to messages you received.
    public func shouldHide(text: String, authorId: EnginePeer.Id?, peerId: EnginePeer.Id, isIncoming: Bool) -> Bool {
        if !self.hiddenSenderIds.isEmpty, let authorId = authorId, authorId != self.accountPeerId, self.hiddenSenderIds.contains(authorId.toInt64()) {
            return true
        }
        if !self.rules.isEmpty, isIncoming, !self.filterDisabledPeerIds.contains(peerId.toInt64()), RGMessageFilter.shouldHide(text: text, peerId: peerId.toInt64(), rules: self.rules) {
            return true
        }
        return false
    }

    /// Memoised form, for the callers that run over a whole window on every rebuild.
    ///
    /// Prefer this over the plain `shouldHide` wherever a message id is at hand: it is the same
    /// predicate, but a window that was already examined costs one dictionary lookup per entry
    /// rather than a Unicode-folding search per entry per rule.
    public func shouldHide(messageId: EngineMessage.Id, stableVersion: UInt32, text: String, authorId: EnginePeer.Id?, isIncoming: Bool) -> Bool {
        if let cached = RGContentFilterVerdictCache.shared.verdict(for: messageId, generation: self.generation, stableVersion: stableVersion) {
            return cached
        }
        let result = self.shouldHide(text: text, authorId: authorId, peerId: messageId.peerId, isIncoming: isIncoming)
        RGContentFilterVerdictCache.shared.store(result, for: messageId, generation: self.generation, stableVersion: stableVersion)
        return result
    }

    public func shouldHide(message: EngineMessage) -> Bool {
        return self.shouldHide(messageId: message.id, stableVersion: message.stableVersion, text: message.text, authorId: message.author?.id, isIncoming: message.effectivelyIncoming(self.accountPeerId))
    }
}

/// Emits on every message-filter / hidden-sender change, and **never emits an initial value**. Both
/// the chat history and the chat list are driven by signal chains that only react to Postbox
/// updates, so this is what makes a newly added rule take effect right away rather than at the next
/// unrelated update.
///
/// The absence of an initial value is deliberate: consumers attach it with `then` so that the data
/// they were already going to deliver passes through untouched and this signal can only ever *add*
/// re-deliveries. Combining it with `combineLatest` instead would make the first delivery of a chat
/// history depend on this signal having produced a value, which is not a dependency the chat screen
/// should ever have.
public func rgContentFiltersDidChange() -> Signal<Void, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: nil, using: { _ in
            subscriber.putNext(Void())
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

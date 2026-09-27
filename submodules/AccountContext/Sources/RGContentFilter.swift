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
/// Chat history transitions run on the main thread. Their history windows are evaluated first on a
/// dedicated queue, so layout only reads cached verdicts instead of running a regex while scrolling.
///
/// A verdict stays valid until either the rules or the message itself change. Rule changes are
/// caught by `RGSimpleSettings.contentFilterGeneration`, which discards the whole table; message
/// changes are caught by Postbox's `stableVersion`, which it increments on every update of a message
/// (`MessageHistoryTable`: `stableVersion = previousMessage.stableVersion + 1`). That makes an edit
/// exact rather than heuristic — comparing text length instead would serve a stale verdict for an
/// edit that happened to preserve it, and a stale *hide* means a message the user never sees.
private final class RGContentFilterVerdictCache {
    static let shared = RGContentFilterVerdictCache()

    private struct Key: Hashable {
        let accountPeerId: EnginePeer.Id
        let messageId: EngineMessage.Id
        let generation: Int
    }

    private struct Entry {
        let stableVersion: UInt32
        let shouldHide: Bool
    }

    /// Bounded so that a long session cannot grow it without limit. Far above what one rebuild
    /// touches, so the clear below is rare rather than a thrash.
    private let limit = 8192

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var evictionOrder: [Key] = []
    private var nextEviction = 0
    private var pending = Set<Key>()
    private var refreshScheduled = false

    func verdict(for id: EngineMessage.Id, accountPeerId: EnginePeer.Id, generation: Int, stableVersion: UInt32) -> Bool? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let entry = self.entries[Key(accountPeerId: accountPeerId, messageId: id, generation: generation)], entry.stableVersion == stableVersion else {
            return nil
        }
        return entry.shouldHide
    }

    func store(_ shouldHide: Bool, for id: EngineMessage.Id, accountPeerId: EnginePeer.Id, generation: Int, stableVersion: UInt32) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let key = Key(accountPeerId: accountPeerId, messageId: id, generation: generation)
        if self.entries[key] == nil {
            if self.evictionOrder.count == self.limit {
                self.entries.removeValue(forKey: self.evictionOrder[self.nextEviction])
                self.evictionOrder[self.nextEviction] = key
                self.nextEviction = (self.nextEviction + 1) % self.limit
            } else {
                self.evictionOrder.append(key)
            }
        }
        self.entries[key] = Entry(stableVersion: stableVersion, shouldHide: shouldHide)
    }

    func schedule(for id: EngineMessage.Id, accountPeerId: EnginePeer.Id, generation: Int, compute: @escaping () -> Void) {
        let key = Key(accountPeerId: accountPeerId, messageId: id, generation: generation)
        self.lock.lock()
        let inserted = self.pending.insert(key).inserted
        self.lock.unlock()
        guard inserted else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            compute()
            self.lock.lock()
            self.pending.remove(key)
            let shouldNotify = !self.refreshScheduled
            self.refreshScheduled = true
            self.lock.unlock()
            if shouldNotify {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    self.lock.lock()
                    self.refreshScheduled = false
                    self.lock.unlock()
                    NotificationCenter.default.post(name: RGSimpleSettings.contentFilterResultsDidChangeNotification, object: nil)
                }
            }
        }
    }
}

public struct RGContentFilterState {
    public let rules: [RGMessageFilterRule]
    private let matcher: RGMessageFilterMatcher
    public let hiddenSenderIds: Set<Int64>
    /// Chats the keyword rules are switched off in, from the per-chat toggle on a peer's profile.
    /// Hidden senders are deliberately *not* subject to it: hiding someone is about the person, so
    /// it has to hold everywhere they post.
    public let filterDisabledPeerIds: Set<Int64>
    public let accountPeerId: EnginePeer.Id

    /// Generation the verdict cache is keyed on, captured with the rules so that a rule change
    /// landing mid-pass cannot mix verdicts from two rule sets into one table.
    public let generation: Int

    /// A single snapshot keeps the compiled rules, scopes, blocked senders and generation aligned.
    public init(accountPeerId: EnginePeer.Id) {
        let settings = RGSimpleSettings.shared
        let snapshot = settings.contentFilterSnapshot()
        let matcher = snapshot.isProUnlocked ? snapshot.matcher : RGMessageFilterMatcher(rules: [])
        self.matcher = matcher
        self.rules = matcher.rules
        self.hiddenSenderIds = snapshot.isProUnlocked ? snapshot.blockedPeerIds : []
        self.filterDisabledPeerIds = snapshot.disabledPeerIds
        self.accountPeerId = accountPeerId
        self.generation = snapshot.generation
    }

    public var isEmpty: Bool {
        return self.matcher.isEmpty && self.hiddenSenderIds.isEmpty
    }

    /// - Parameters:
    ///   - authorId: the sender. Hidden senders are matched on this so a user hidden from their
    ///     profile disappears from every group and comment thread, not just a one-to-one chat.
    ///   - peerId: the conversation, used to apply rules scoped to specific chats.
    ///   - isIncoming: keyword rules only apply to messages you received.
    public func shouldHide(text: String, authorId: EnginePeer.Id?, peerId: EnginePeer.Id, isIncoming: Bool, isCancelled: () -> Bool = { false }) -> Bool {
        if !self.hiddenSenderIds.isEmpty, let authorId = authorId, authorId != self.accountPeerId, self.hiddenSenderIds.contains(authorId.toInt64()) {
            return true
        }
        if !self.matcher.isEmpty, isIncoming, !self.filterDisabledPeerIds.contains(peerId.toInt64()), self.matcher.shouldHide(text: text, peerId: peerId.toInt64(), isCancelled: isCancelled) {
            return true
        }
        return false
    }

    /// Memoised form, for the callers that run over a whole window on every rebuild.
    ///
    /// Prefer this over the plain `shouldHide` wherever a message id is at hand: it is the same
    /// predicate, but a window that was already examined costs one dictionary lookup per entry
    /// rather than a Unicode-folding search per entry per rule.
    public func shouldHide(messageId: EngineMessage.Id, stableVersion: UInt32, text: String, authorId: EnginePeer.Id?, isIncoming: Bool, isCancelled: () -> Bool = { false }) -> Bool {
        if let cached = RGContentFilterVerdictCache.shared.verdict(for: messageId, accountPeerId: self.accountPeerId, generation: self.generation, stableVersion: stableVersion) {
            return cached
        }
        if Thread.isMainThread && !self.isEmpty {
            let hiddenSender = !self.hiddenSenderIds.isEmpty && authorId.map { $0 != self.accountPeerId && self.hiddenSenderIds.contains($0.toInt64()) } == true
            if hiddenSender { return true }
            guard isIncoming else { return false }
            RGContentFilterVerdictCache.shared.schedule(for: messageId, accountPeerId: self.accountPeerId, generation: self.generation) {
                guard RGSimpleSettings.shared.contentFilterGeneration == self.generation else { return }
                let result = self.shouldHide(text: text, authorId: authorId, peerId: messageId.peerId, isIncoming: isIncoming, isCancelled: { RGSimpleSettings.shared.contentFilterGeneration != self.generation })
                guard RGSimpleSettings.shared.contentFilterGeneration == self.generation else { return }
                RGContentFilterVerdictCache.shared.store(result, for: messageId, accountPeerId: self.accountPeerId, generation: self.generation, stableVersion: stableVersion)
            }
            // No main-thread regex fallback. The prepared result triggers a fresh presentation pass.
            return false
        }
        let result = self.shouldHide(text: text, authorId: authorId, peerId: messageId.peerId, isIncoming: isIncoming, isCancelled: isCancelled)
        if isCancelled() { return false }
        RGContentFilterVerdictCache.shared.store(result, for: messageId, accountPeerId: self.accountPeerId, generation: self.generation, stableVersion: stableVersion)
        return result
    }

    public func shouldHide(message: EngineMessage) -> Bool {
        return self.shouldHide(messageId: message.id, stableVersion: message.stableVersion, text: message.text, authorId: message.author?.id, isIncoming: message.effectivelyIncoming(self.accountPeerId))
    }

    public func preparedVerdict(messageId: EngineMessage.Id, stableVersion: UInt32) -> Bool? {
        return RGContentFilterVerdictCache.shared.verdict(for: messageId, accountPeerId: self.accountPeerId, generation: self.generation, stableVersion: stableVersion)
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
        let observers = [RGSimpleSettings.contentFiltersDidChangeNotification, RGSimpleSettings.contentFilterResultsDidChangeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil, using: { _ in subscriber.putNext(Void()) })
        }
        return ActionDisposable {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

public func rgPrepareContentFilter(messages: [EngineMessage], accountPeerId: EnginePeer.Id) -> Signal<Void, NoError> {
    return Signal { subscriber in
        let cancelled = Atomic<Bool>(value: false)
        DispatchQueue.global(qos: .userInitiated).async {
            let filter = RGContentFilterState(accountPeerId: accountPeerId)
            let isCancelled = { cancelled.with { $0 } || RGSimpleSettings.shared.contentFilterGeneration != filter.generation }
            if !filter.isEmpty {
                for message in messages {
                    if isCancelled() { return }
                    let _ = filter.shouldHide(messageId: message.id, stableVersion: message.stableVersion, text: message.text, authorId: message.author?.id, isIncoming: message.effectivelyIncoming(accountPeerId), isCancelled: isCancelled)
                }
            }
            if !isCancelled() {
                subscriber.putNext(Void())
                subscriber.putCompletion()
            }
        }
        return ActionDisposable { let _ = cancelled.swap(true) }
    }
}

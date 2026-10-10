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
///
/// `stableVersion` also moves for updates that leave the text alone — view counts, reactions, read
/// markers — which in a channel arrive continuously for exactly the posts on screen. The filter only
/// reads the text, so each entry also remembers a hash of it, and a new version with the same text
/// keeps its verdict instead of being matched against every rule again.
private final class RGContentFilterVerdictCache {
    static let shared = RGContentFilterVerdictCache()

    private struct Entry {
        var stableVersion: UInt32
        let textHash: Int
        let shouldHide: Bool
    }

    /// Bounded so that a long session cannot grow it without limit. Evicted oldest-first, one entry
    /// at a time: dropping the whole table at the limit (as this used to) made the next rebuild
    /// re-match the entire window in one go, mid-scroll.
    private let limit = 8192

    private let lock = NSLock()
    private var generation: Int = -1
    private var entries: [EngineMessage.Id: Entry] = [:]
    private var insertionOrder: [EngineMessage.Id] = []
    private var nextEviction = 0

    func verdict(for id: EngineMessage.Id, generation: Int, stableVersion: UInt32) -> Bool? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.generation == generation, let entry = self.entries[id], entry.stableVersion == stableVersion else {
            return nil
        }
        return entry.shouldHide
    }

    /// Same as above, but also accepts an entry for an older version of the message whose text is
    /// unchanged, and records the new version so the plain lookup hits from now on.
    func verdict(for id: EngineMessage.Id, generation: Int, stableVersion: UInt32, textHash: Int) -> Bool? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.generation == generation, var entry = self.entries[id] else {
            return nil
        }
        if entry.stableVersion != stableVersion {
            guard entry.textHash == textHash else {
                return nil
            }
            entry.stableVersion = stableVersion
            self.entries[id] = entry
        }
        return entry.shouldHide
    }

    func store(_ shouldHide: Bool, for id: EngineMessage.Id, generation: Int, stableVersion: UInt32, textHash: Int) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if generation < self.generation {
            // Computed under rules that have since changed (a background pass finishing late).
            // Storing it would reset the table to the old generation and throw the new one away.
            return
        }
        if self.generation != generation {
            self.generation = generation
            self.entries.removeAll(keepingCapacity: true)
            self.insertionOrder.removeAll(keepingCapacity: true)
            self.nextEviction = 0
        }
        if self.entries[id] == nil {
            if self.insertionOrder.count == self.limit {
                self.entries.removeValue(forKey: self.insertionOrder[self.nextEviction])
                self.insertionOrder[self.nextEviction] = id
                self.nextEviction = (self.nextEviction + 1) % self.limit
            } else {
                self.insertionOrder.append(id)
            }
        }
        self.entries[id] = Entry(stableVersion: stableVersion, textHash: textHash, shouldHide: shouldHide)
    }

    /// The candidates without a verdict for their current version, found under one lock.
    func missing(_ candidates: [RGContentFilterCandidate], generation: Int) -> [RGContentFilterCandidate] {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.generation == generation else {
            return candidates
        }
        return candidates.filter { candidate in
            guard let entry = self.entries[candidate.id] else {
                return true
            }
            return entry.stableVersion != candidate.stableVersion
        }
    }
}

/// What the filter needs to know about one message, detached from Postbox so a whole history window
/// can be handed to a background queue.
public struct RGContentFilterCandidate {
    public let id: EngineMessage.Id
    public let stableVersion: UInt32
    public let text: String
    public let authorId: EnginePeer.Id?
    public let isIncoming: Bool

    public init(id: EngineMessage.Id, stableVersion: UInt32, text: String, authorId: EnginePeer.Id?, isIncoming: Bool) {
        self.id = id
        self.stableVersion = stableVersion
        self.text = text
        self.authorId = authorId
        self.isIncoming = isIncoming
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
    public let temporarilyVisiblePeerIds: Set<Int64>

    /// Generation the verdict cache is keyed on, captured with the rules so that a rule change
    /// landing mid-pass cannot mix verdicts from two rule sets into one table.
    fileprivate let generation: Int

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
        self.temporarilyVisiblePeerIds = settings.temporarilyVisiblePeerIds(accountId: accountPeerId.toInt64())
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
        // MARK: Regram — explicit temporary recovery is local display only; notifications stay filtered.
        if self.temporarilyVisiblePeerIds.contains(peerId.toInt64()) { return false }
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
        let cache = RGContentFilterVerdictCache.shared
        if let cached = cache.verdict(for: messageId, generation: self.generation, stableVersion: stableVersion) {
            return cached
        }
        let textHash = text.hashValue
        if let cached = cache.verdict(for: messageId, generation: self.generation, stableVersion: stableVersion, textHash: textHash) {
            return cached
        }
        let result = self.shouldHide(text: text, authorId: authorId, peerId: messageId.peerId, isIncoming: isIncoming)
        cache.store(result, for: messageId, generation: self.generation, stableVersion: stableVersion, textHash: textHash)
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

/// Computes the verdicts for `candidates` on `queue`, so that a following main-thread pass over the
/// same messages (`chatHistoryEntriesForView`) only reads the cache.
///
/// Matching is a case-insensitive search or a regex per rule per message. Done inline on the main
/// thread, as it used to be, every history window that moved while scrolling matched its newly
/// loaded messages right inside the frame — the stutter of slow scrolling. Completes synchronously,
/// with no queue hop, when the filter is off or every candidate already has a verdict, so the
/// common case costs nothing. Meant for `mapToQueue`, which keeps updates in order and never drops
/// one: the first update of a history view carries its scroll position.
public func rgPrepareContentFilter(candidates: [RGContentFilterCandidate], accountPeerId: EnginePeer.Id, queue: Queue) -> Signal<Void, NoError> {
    let filter = RGContentFilterState(accountPeerId: accountPeerId)
    if filter.isEmpty {
        return .single(Void())
    }
    let cache = RGContentFilterVerdictCache.shared
    let missing = cache.missing(candidates, generation: filter.generation)
    if missing.isEmpty {
        return .single(Void())
    }
    return Signal { subscriber in
        queue.async {
            for candidate in missing {
                let _ = filter.shouldHide(messageId: candidate.id, stableVersion: candidate.stableVersion, text: candidate.text, authorId: candidate.authorId, isIncoming: candidate.isIncoming)
            }
            subscriber.putNext(Void())
            subscriber.putCompletion()
        }
        return EmptyDisposable
    }
}

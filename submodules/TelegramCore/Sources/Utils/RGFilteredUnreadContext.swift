import Foundation
import Postbox
import SwiftSignalKit
import RGSimpleSettings

public struct RGFilteredChatKey: Hashable {
    public let peerId: PeerId
    public let threadId: Int64?
    public init(peerId: PeerId, threadId: Int64? = nil) { self.peerId = peerId; self.threadId = threadId }
}

public struct RGFilteredChatResult {
    public let topId: MessageId?
    public let preview: EngineMessage?
    public let hiddenUnread: [MessageIndex]
    public let original: EnginePeerReadCounters
    public let isMuted: Bool
    public let hiddenByNamespace: [MessageId.Namespace: Int32]

    public func counters(_ counters: EnginePeerReadCounters) -> EnginePeerReadCounters {
        guard let state = counters._asReadCounters() else { return counters }
        var hidden = self.hiddenByNamespace
        if counters._asReadCounters() != self.original._asReadCounters() {
            hidden = [:]
            for index in self.hiddenUnread where !counters.isIncomingMessageIndexRead(index) { hidden[index.id.namespace, default: 0] += 1 }
        }
        let states = state.states.map { namespace, value -> (MessageId.Namespace, PeerReadState) in
            let reduction = min(max(0, value.count), hidden[namespace] ?? 0)
            switch value {
            case let .idBased(incoming, outgoing, known, count, marked):
                return (namespace, .idBased(maxIncomingReadId: incoming, maxOutgoingReadId: outgoing, maxKnownId: known, count: count - reduction, markedUnread: marked))
            case let .indexBased(incoming, outgoing, count, marked):
                return (namespace, .indexBased(maxIncomingReadIndex: incoming, maxOutgoingReadIndex: outgoing, count: count - reduction, markedUnread: marked))
            }
        }
        return EnginePeerReadCounters(state: CombinedPeerReadState(states: states), isMuted: counters.isMuted)
    }
}

public struct RGFilteredUnreadSnapshot {
    public init() {}
    public var isReady = false
    /// Set during invalidation before the first background scan. Callers can keep the upstream
    /// fast path when no filter is active instead of enumerating every unread chat on every action.
    public var filteringEnabled = false
    public struct PeerMetadata {
        public let groupId: PeerGroupId
        public let tags: PeerSummaryCounterTags
        public let isMuted: Bool
        public let threadBased: Bool
        public let effectiveThreadCount: Int32
    }
    public var chats: [RGFilteredChatKey: RGFilteredChatResult] = [:]
    public var peers: [PeerId: PeerMetadata] = [:]
    public var threadsByPeer: [PeerId: [Int64]] = [:]
    public var countedThreadsByPeer: [PeerId: [Int64]] = [:]
    public var generation = 0

    public func displayCount(peerId: PeerId, threadId: Int64? = nil, serverCount: Int32) -> Int32 {
        if let result = self.chats[RGFilteredChatKey(peerId: peerId, threadId: threadId)] {
            guard result.original.count == serverCount else { return serverCount }
            return result.counters(result.original).count
        }
        if threadId == nil, self.peers[peerId]?.threadBased == true {
            let topics = (self.countedThreadsByPeer[peerId] ?? []).compactMap { self.chats[RGFilteredChatKey(peerId: peerId, threadId: $0)] }
            let hasVisibleUnread = topics.contains { !$0.counters($0.original).isMuted && $0.counters($0.original).isUnread }
            // The parent forum summary is a chat-level 0/1 counter. Removing every hidden
            // topic individually would turn a parent with one visible topic and one hidden topic
            // into zero, even though the parent must remain unread.
            return hasVisibleUnread ? serverCount : max(0, serverCount - ((self.peers[peerId]?.effectiveThreadCount ?? 0) > 0 ? 1 : 0))
        }
        return serverCount
    }

    public func removedChats(groupId: PeerGroupId) -> Int {
        return self.peers.filter { $0.value.groupId == groupId }.reduce(0) { count, peer in
            if peer.value.threadBased {
                let topics = (self.countedThreadsByPeer[peer.key] ?? []).compactMap { self.chats[RGFilteredChatKey(peerId: peer.key, threadId: $0)] }
                let hasOriginalUnread = topics.contains { !$0.original.isMuted && $0.original.isUnread }
                let hasVisibleUnread = topics.contains { !$0.counters($0.original).isMuted && $0.counters($0.original).isUnread }
                return count + (hasOriginalUnread && !hasVisibleUnread ? 1 : 0)
            }
            guard let value = self.chats[RGFilteredChatKey(peerId: peer.key)] else { return count }
            guard !peer.value.isMuted else { return count }
            return count + (value.original.isUnread && !value.counters(value.original).isUnread ? 1 : 0)
        }
    }

    public func counters(peerId: PeerId, threadId: Int64? = nil, original: EnginePeerReadCounters) -> EnginePeerReadCounters {
        if let result = self.chats[RGFilteredChatKey(peerId: peerId, threadId: threadId)] { return result.counters(original) }
        if threadId == nil, self.peers[peerId]?.threadBased == true {
            let topics = (self.countedThreadsByPeer[peerId] ?? []).compactMap { self.chats[RGFilteredChatKey(peerId: peerId, threadId: $0)] }
            let hasVisibleUnread = topics.contains { !$0.counters($0.original).isMuted && $0.counters($0.original).isUnread }
            let removed = !hasVisibleUnread && (self.peers[peerId]?.effectiveThreadCount ?? 0) > 0 && original.isUnread && !original.markedUnread ? 1 : 0
            guard removed > 0, let state = original._asReadCounters() else { return original }
            let states = state.states.map { ns, value -> (MessageId.Namespace, PeerReadState) in
                switch value {
                case let .idBased(i, o, k, n, m): return (ns, .idBased(maxIncomingReadId: i, maxOutgoingReadId: o, maxKnownId: k, count: max(0, n - Int32(removed)), markedUnread: m))
                case let .indexBased(i, o, n, m): return (ns, .indexBased(maxIncomingReadIndex: i, maxOutgoingReadIndex: o, count: max(0, n - Int32(removed)), markedUnread: m))
                }
            }
            return EnginePeerReadCounters(state: CombinedPeerReadState(states: states), isMuted: original.isMuted)
        }
        return original
    }

    public func adjustedTotal(_ total: ChatListTotalUnreadState, groupId: PeerGroupId) -> ChatListTotalUnreadState {
        var result = total
        for (peerId, metadata) in self.peers where metadata.groupId == groupId {
            var messages: Int32 = 0
            var chats: Int32 = 0
            if metadata.threadBased {
                let topics = (self.countedThreadsByPeer[peerId] ?? []).compactMap { self.chats[RGFilteredChatKey(peerId: peerId, threadId: $0)] }
                let hasUnread = topics.contains { !$0.isMuted && $0.counters($0.original).isUnread }
                if !topics.isEmpty && !hasUnread && metadata.effectiveThreadCount > 0 {
                    messages = metadata.effectiveThreadCount
                    chats = 1
                }
            } else if let value = self.chats[RGFilteredChatKey(peerId: peerId)] {
                let adjusted = value.counters(value.original)
                messages = max(value.original.count, value.original.markedUnread ? 1 : 0) - max(adjusted.count, adjusted.markedUnread ? 1 : 0)
                if value.original.isUnread && !adjusted.isUnread { chats = 1 }
            }
            for tag in metadata.tags {
                if var value = result.absoluteCounters[tag] {
                    value.messageCount = max(0, value.messageCount - messages)
                    value.chatCount = max(0, value.chatCount - chats)
                    result.absoluteCounters[tag] = value
                }
                if !metadata.isMuted, var value = result.filteredCounters[tag] {
                    value.messageCount = max(0, value.messageCount - messages)
                    value.chatCount = max(0, value.chatCount - chats)
                    result.filteredCounters[tag] = value
                }
            }
        }
        return result
    }
}

/// One incremental projection per account. Only affected peers are rescanned. Each database read
/// is a bounded range; matching happens on this worker queue, never in a Postbox transaction.
public final class RGFilteredUnreadContext {
    private let postbox: Postbox
    private let accountPeerId: PeerId
    private let queue = Queue(name: "regram.filtered-unread", qos: .utility)
    private let changesDisposable = MetaDisposable()
    private let scanDisposable = MetaDisposable()
    private let signalValue = Promise<RGFilteredUnreadSnapshot>(RGFilteredUnreadSnapshot())
    private var snapshot = RGFilteredUnreadSnapshot()
    private let currentValue = Atomic(value: RGFilteredUnreadSnapshot())
    private var pending = Set<PeerId>()
    private var activePeer: PeerId?
    private var loadingAll = false
    private var publishScheduled = false
    private var lastPublished: TimeInterval = 0.0
    private var epoch = 0
    private var observer: NSObjectProtocol?
    private var cancelled = Atomic<Bool>(value: false)

    public var state: Signal<RGFilteredUnreadSnapshot, NoError> { self.signalValue.get() }
    public var current: RGFilteredUnreadSnapshot { self.currentValue.with { $0 } }

    public init(postbox: Postbox, accountPeerId: PeerId) {
        self.postbox = postbox
        self.accountPeerId = accountPeerId
        self.changesDisposable.set((postbox.contentFilterChanges |> deliverOn(self.queue)).start(next: { [weak self] peers in self?.invalidate(peers) }))
        self.observer = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in self?.invalidate(nil) }
        }
        self.queue.async { [weak self] in self?.invalidate(nil) }
    }
    deinit {
        let _ = self.cancelled.swap(true)
        self.changesDisposable.dispose()
        self.scanDisposable.dispose()
        if let observer = self.observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func invalidate(_ peerIds: Set<PeerId>?) {
        if self.loadingAll, peerIds != nil { self.invalidate(nil); return }
        if let peerIds, self.activePeer.map({ !peerIds.contains($0) }) ?? true {
            self.pending.formUnion(peerIds)
            self.snapshot.chats = self.snapshot.chats.filter { !peerIds.contains($0.key.peerId) }
            for peerId in peerIds { self.snapshot.peers.removeValue(forKey: peerId); self.snapshot.threadsByPeer.removeValue(forKey: peerId); self.snapshot.countedThreadsByPeer.removeValue(forKey: peerId) }
            self.publish()
            self.next()
            return
        }
        self.epoch += 1
        let _ = self.cancelled.swap(true)
        self.cancelled = Atomic(value: false)
        self.scanDisposable.set(nil)
        if let activePeer = self.activePeer { self.pending.insert(activePeer) }
        self.activePeer = nil
        if let peerIds {
            self.pending.formUnion(peerIds)
            self.snapshot.chats = self.snapshot.chats.filter { !peerIds.contains($0.key.peerId) }
            for peerId in peerIds { self.snapshot.peers.removeValue(forKey: peerId); self.snapshot.threadsByPeer.removeValue(forKey: peerId); self.snapshot.countedThreadsByPeer.removeValue(forKey: peerId) }
            self.publish()
            self.next()
        } else {
            self.loadingAll = true
            self.snapshot = RGFilteredUnreadSnapshot()
            self.pending.removeAll()
            let settings = RGSimpleSettings.shared.contentFilterSnapshot()
            self.snapshot.generation = settings.generation
            self.snapshot.filteringEnabled = settings.isProUnlocked && (!settings.matcher.isEmpty || !settings.blockedPeerIds.isEmpty)
            self.publish()
            guard self.snapshot.filteringEnabled else { self.loadingAll = false; self.publish(); return }
            let epoch = self.epoch
            self.scanDisposable.set((self.postbox.transaction { transaction in
                return Set((transaction.getChatListPeers(groupId: .root, filterPredicate: nil, additionalFilter: nil) + transaction.getChatListPeers(groupId: Namespaces.PeerGroup.archive, filterPredicate: nil, additionalFilter: nil)).map { $0.id })
            } |> deliverOn(self.queue)).start(next: { [weak self] peers in
                guard let self, self.epoch == epoch else { return }
                self.loadingAll = false
                self.pending.formUnion(peers)
                self.next()
            }))
        }
    }

    private func publish() {
        self.snapshot.isReady = !self.loadingAll && self.pending.isEmpty && self.activePeer == nil
        let now = ProcessInfo.processInfo.systemUptime
        if !self.snapshot.isReady && now - self.lastPublished < 0.1 {
            if !self.publishScheduled {
                self.publishScheduled = true
                self.queue.after(0.1) { [weak self] in self?.publishScheduled = false; self?.publish() }
            }
            return
        }
        self.lastPublished = now
        let _ = self.currentValue.swap(self.snapshot)
        self.signalValue.set(.single(self.snapshot))
    }

    private struct Scan {
        let key: RGFilteredChatKey
        let counters: EnginePeerReadCounters
        let muted: Bool
        let namespaces: [MessageId.Namespace]
    }
    private func next() {
        guard self.activePeer == nil else { return }
        guard let peerId = self.pending.first else { self.publish(); return }
        self.pending.remove(peerId)
        self.activePeer = peerId
        let epoch = self.epoch
        let settings = RGSimpleSettings.shared.contentFilterSnapshot()
        guard settings.isProUnlocked && (!settings.matcher.isEmpty || !settings.blockedPeerIds.isEmpty) else {
            self.activePeer = nil; self.pending.removeAll(); return
        }
        self.scanDisposable.set((self.postbox.transaction { transaction -> (RGFilteredUnreadSnapshot.PeerMetadata?, [Scan]) in
            guard let info = transaction.contentFilterPeerMetadata(peerId) else { return (nil, []) }
            let metadata = RGFilteredUnreadSnapshot.PeerMetadata(groupId: info.groupId, tags: info.tags, isMuted: info.isMuted, threadBased: info.threadBased, effectiveThreadCount: info.effectiveThreadCount)
            if info.threadBased {
                let scans = transaction.getMessageHistoryThreadIndex(peerId: peerId, limit: 1000).compactMap { item -> Scan? in
                    guard let data = item.info.data.get(MessageHistoryThreadData.self) else { return nil }
                    let muted: Bool
                    switch data.notificationSettings.muteState { case .muted: muted = true; case .unmuted: muted = false; case .default: muted = info.isMuted }
                    var counters = EnginePeerReadCounters(incomingReadId: data.maxIncomingReadId, outgoingReadId: data.maxOutgoingReadId, count: data.incomingUnreadCount, markedUnread: data.isMarkedUnread)
                    counters.isMuted = muted
                    return Scan(key: RGFilteredChatKey(peerId: peerId, threadId: item.threadId), counters: counters, muted: muted, namespaces: [Namespaces.Message.Cloud])
                }
                return (metadata, scans)
            }
            let state = transaction.getCombinedPeerReadState(peerId)
            var namespaces = state?.states.map { $0.0 } ?? [Namespaces.Message.Cloud]
            if namespaces.isEmpty { namespaces = [Namespaces.Message.Cloud] }
            return (metadata, [Scan(key: RGFilteredChatKey(peerId: peerId), counters: EnginePeerReadCounters(state: state, isMuted: info.isMuted), muted: info.isMuted, namespaces: namespaces)])
        } |> deliverOn(self.queue)).start(next: { [weak self] metadata, scans in
            guard let self, self.epoch == epoch else { return }
            if let metadata { self.snapshot.peers[peerId] = metadata }
            self.snapshot.threadsByPeer[peerId] = scans.compactMap { $0.key.threadId }
            // The upstream parent summary counts its first 20 topics. Subtract only contributors
            // represented in that summary; every topic still gets its own complete projection.
            self.snapshot.countedThreadsByPeer[peerId] = Array(scans.prefix(20)).compactMap { $0.key.threadId }
            self.scanTasks(scans, index: 0, settings: settings, epoch: epoch)
        }))
    }

    private func scanTasks(_ scans: [Scan], index: Int, settings: RGContentFilterSettingsSnapshot, epoch: Int) {
        guard self.epoch == epoch else { return }
        guard index < scans.count else {
            self.publish()
            self.activePeer = nil
            self.next()
            return
        }
        self.scanPage(scans, index: index, namespaceIndex: 0, before: nil, result: ScanAccumulator(), settings: settings, epoch: epoch)
    }

    private final class ScanAccumulator {
        var preview: EngineMessage?
        var top: MessageId?
        var topIndex: MessageIndex?
        var hidden: [MessageIndex] = []
        var hiddenByNamespace: [MessageId.Namespace: Int32] = [:]
    }
    private func scanPage(_ scans: [Scan], index: Int, namespaceIndex: Int, before: MessageIndex?, result: ScanAccumulator, settings: RGContentFilterSettingsSnapshot, epoch: Int) {
        guard self.epoch == epoch else { return }
        let scan = scans[index]
        guard namespaceIndex < scan.namespaces.count else {
            self.snapshot.chats[scan.key] = RGFilteredChatResult(topId: result.top, preview: result.preview, hiddenUnread: result.hidden, original: scan.counters, isMuted: scan.muted, hiddenByNamespace: result.hiddenByNamespace)
            self.scanTasks(scans, index: index + 1, settings: settings, epoch: epoch)
            return
        }
        let cancellation = self.cancelled
        self.scanDisposable.set((self.postbox.transaction { transaction in
            transaction.localMessagePage(peerId: scan.key.peerId, namespace: scan.namespaces[namespaceIndex], threadId: scan.key.threadId, before: before, limit: 64)
        } |> deliverOn(self.queue)).start(next: { [weak self] messages in
            guard let self, self.epoch == epoch else { return }
            var reachedRead = scan.counters.count == 0
            for message in messages {
                if cancellation.with({ $0 }) { return }
                if result.topIndex == nil || message.index > result.topIndex! { result.top = message.id; result.topIndex = message.index }
                let blocked = message.author.map { $0.id != self.accountPeerId && settings.blockedPeerIds.contains($0.id.toInt64()) } ?? false
                let matched = blocked || (message.effectivelyIncoming(self.accountPeerId) && !settings.disabledPeerIds.contains(scan.key.peerId.toInt64()) && settings.matcher.shouldHide(text: message.text, peerId: scan.key.peerId.toInt64(), isCancelled: { cancellation.with { $0 } || RGSimpleSettings.shared.contentFilterGeneration != settings.generation }))
                if !matched && (result.preview == nil || message.index > result.preview!.index) { result.preview = EngineMessage(message) }
                if message.flags.contains(.Incoming) {
                    if scan.counters.isIncomingMessageIndexRead(message.index) { reachedRead = true }
                    else if matched { result.hidden.append(message.index); result.hiddenByNamespace[message.id.namespace, default: 0] += 1 }
                }
            }
            if messages.count == 64 && !(reachedRead && result.preview != nil), let last = messages.last {
                self.scanPage(scans, index: index, namespaceIndex: namespaceIndex, before: last.index, result: result, settings: settings, epoch: epoch)
            } else {
                self.scanPage(scans, index: index, namespaceIndex: namespaceIndex + 1, before: nil, result: result, settings: settings, epoch: epoch)
            }
        }))
    }
}

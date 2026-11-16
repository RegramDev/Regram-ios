// MARK: Regram — apply the account's ad projection before text, emoji and thumbnails are rendered.
import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext

/// This stage changes display messages only. Ordering, drafts, unread state and the stored messages
/// stay intact. It runs after legacy keyword substitution and never sends read receipts.
final class RGChatListAdPreview {
    private struct Recent {
        let top: [EngineMessage]
        let messages: [EngineMessage]
        var count: Int

        mutating func advance() {
            count = min(messages.count, count + 1)
            // Keep an album together so its caption can decide its otherwise empty attachments.
            while count > 0, count < messages.count, let key = messages[count - 1].groupingKey, messages[count].groupingKey == key { count += 1 }
        }
    }
    private let context: AccountContext
    private let queue: Queue
    private let session: RGAdFilterSession
    private let scope = RGAdFilterSession.Scope.chatList(UUID())
    // Accessed on the view processing queue; raw originals allow corrections/settings to reproject.
    private var recent: [EnginePeer.Id: Recent] = [:]

    init(context: AccountContext, queue: Queue) {
        self.context = context; self.queue = queue; self.session = RGAdFilterSession.get(context)
    }

    deinit { session.release(scope: scope) }

    func apply(to update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
        let items = update.list.items + update.list.additionalItems.map(\.item)
        let visible = Set(items.compactMap { item -> EnginePeer.Id? in
            if case let .chatList(peerId) = item.id { return peerId }; return nil
        })
        recent = recent.filter { visible.contains($0.key) }
        for item in items {
            if case let .chatList(peerId) = item.id, let cached = recent[peerId], cached.top != item.messages { recent.removeValue(forKey: peerId) }
        }
        // A result for one row must not wait for all other rows. Each subscription owns
        // cancellable preparation/loading; the helper retains only this view's recent cache.
        return Signal { [self] subscriber in
            let work = PreviewWork(owner: self, update: update, emit: subscriber.putNext, complete: subscriber.putCompletion)
            work.advance()
            return ActionDisposable {
                if self.queue.isCurrent() { work.stop() }
                else { self.queue.async { work.stop() } }
            }
        } |> rgChatListPreviewUpdates()
    }

    private func sourceMessages(_ update: ChatListNodeViewUpdate) -> [Message] {
        let items = (update.list.items + update.list.additionalItems.map(\.item)).sorted { $0.index > $1.index }
        var sources: [Message] = [], seen = Set<MessageId>()
        func append(_ message: EngineMessage) {
            if seen.insert(message.id).inserted { sources.append(message._asMessage()) }
        }
        // Keep each row's next fallback beside its top message, so an earlier visible row
        // is not held behind unrelated/offscreen top messages. Stop at the first normal row.
        for item in items {
            for message in item.messages { append(message) }
            if case let .chatList(peerId) = item.id, let cached = recent[peerId], cached.top == item.messages {
                for message in cached.messages.prefix(cached.count) { append(message) }
            }
        }
        for group in update.list.groupItems { if let message = group.topMessage { append(message) } }
        return sources
    }

    /// Advance only past confirmed hidden candidates; unknown/model-unavailable rows are
    /// never certified as normal and never start a busy retry loop.
    private func nextMissing(_ update: ChatListNodeViewUpdate) -> [EnginePeer.Id: [EngineMessage]] {
        let account = context.account.peerId
        let hidden = session.hiddenMessageIds(in: sourceMessages(update), accountPeerId: account, scope: scope)
        let items = (update.list.items + update.list.additionalItems.map(\.item)).sorted { $0.index > $1.index }
        let keywords = RGContentFilterState(accountPeerId: account)
        func visible(_ message: EngineMessage) -> Bool {
            !hidden.contains(message.id) && (keywords.isEmpty || !keywords.shouldHide(message: message))
        }
        for item in items {
            guard case let .chatList(peerId) = item.id, item.messages.allSatisfy({ !visible($0) }),
                  var cached = recent[peerId] else { continue }
            while cached.count < cached.messages.count,
                  cached.messages.prefix(cached.count).allSatisfy({ !visible($0) }) {
                cached.advance()
            }
            recent[peerId] = cached
        }
        var missing: [EnginePeer.Id: [EngineMessage]] = [:]
        for item in items {
            guard case let .chatList(peerId) = item.id, !item.messages.isEmpty, recent[peerId] == nil else { continue }
            // A captionless album top may require the caption carried by another local message.
            if item.messages.allSatisfy({ hidden.contains($0.id) }) || item.messages.contains(where: { $0.groupingKey != nil }) {
                if missing.count < min(16, max(0, 128 - recent.count)) { missing[peerId] = item.messages }
            }
        }
        return missing
    }

    /// Runs on the list processing queue. Progress is coalesced locally instead of posting
    /// a global settings refresh for every newly confirmed normal message.
    private final class PreviewWork {
        let owner: RGChatListAdPreview
        let update: ChatListNodeViewUpdate
        let emit: (ChatListNodeViewUpdate) -> Void
        let complete: () -> Void
        let history = MetaDisposable()
        var request: RGAdWorkRequest?
        var requestedIds: [MessageId]?
        var requestedVersions: [MessageId: UInt32] = [:]
        var generation = 0
        var preparing = false
        var fetching = false
        var scheduled = false
        var stopped = false

        init(owner: RGChatListAdPreview, update: ChatListNodeViewUpdate, emit: @escaping (ChatListNodeViewUpdate) -> Void, complete: @escaping () -> Void) {
            self.owner = owner; self.update = update; self.emit = emit; self.complete = complete
        }

        func stop() {
            stopped = true; generation += 1
            request?.cancel(); request = nil; history.dispose()
        }

        func progressed() {
            guard !stopped, !scheduled else { return }
            scheduled = true
            owner.queue.after(0.05) { [weak self] in
                guard let self else { return }
                self.scheduled = false; self.advance()
            }
        }

        func advance() {
            guard !stopped else { return }
            let missing = owner.nextMissing(update)
            emit(owner.project(update))
            if !fetching, !missing.isEmpty {
                fetching = true
                history.set((owner.context.engine.messages.locallyStoredRecentMessages(peerIds: Array(missing.keys), limit: 50)
                |> deliverOn(owner.queue)).start(next: { [weak self] messages in
                    guard let self, !self.stopped else { return }
                    self.fetching = false
                    for (peerId, top) in missing {
                        guard let newest = top.map(\.index).max() else { continue }
                        var cached = Recent(top: top, messages: (messages[peerId] ?? []).filter { $0.index <= newest }, count: 0)
                        cached.advance(); self.owner.recent[peerId] = cached
                    }
                    self.advance()
                }))
            }
            let messages = owner.sourceMessages(update)
            let ids = messages.map(\.id)
            let versions = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0.stableVersion) })
            if requestedIds != ids || requestedVersions != versions {
                requestedIds = ids; requestedVersions = versions
                generation += 1
                let current = generation
                preparing = true
                let previous = request
                request = owner.session.prepareProgressively(messages, accountPeerId: owner.context.account.peerId, scope: owner.scope, progress: { [weak self] _ in
                    guard let self else { return }
                    self.owner.queue.async { [weak self] in
                        guard let self, current == self.generation else { return }
                        self.progressed()
                    }
                }, completion: { [weak self] in
                    guard let self else { return }
                    self.owner.queue.async { [weak self] in
                        guard let self, !self.stopped, current == self.generation else { return }
                        self.preparing = false; self.advance()
                    }
                })
                previous?.cancel()
            }
            if !preparing && !fetching {
                stopped = true
                complete()
            }
        }

        deinit {
            request?.cancel()
            history.dispose()
        }
    }

    private func project(_ update: ChatListNodeViewUpdate) -> ChatListNodeViewUpdate {
        let account = context.account.peerId
        let hidden = session.hiddenMessageIds(in: sourceMessages(update), accountPeerId: account, scope: scope)
        let keywords = RGContentFilterState(accountPeerId: account)
        func visible(_ message: EngineMessage) -> Bool {
            !hidden.contains(message.id) && (keywords.isEmpty || !keywords.shouldHide(message: message))
        }
        func display(_ message: EngineMessage) -> EngineMessage {
            EngineMessage(session.display(message._asMessage(), accountPeerId: account, scope: scope))
        }
        func item(_ item: EngineChatList.Item) -> EngineChatList.Item {
            var messages = item.messages.filter(visible).map(display)
            if case let .chatList(peerId) = item.id, messages.isEmpty, !item.messages.isEmpty, let cached = recent[peerId], cached.top == item.messages,
               let fallback = cached.messages.prefix(cached.count).first(where: { session.isPrepared($0._asMessage(), accountPeerId: account, scope: scope) && visible($0) }) {
                messages = [display(fallback)]
            }
            guard messages != item.messages else { return item }
            return EngineChatList.Item(
                id: item.id, index: item.index, messages: messages, readCounters: item.readCounters,
                isMuted: item.isMuted, draft: item.draft, threadData: item.threadData,
                renderedPeer: item.renderedPeer, presence: item.presence,
                hasUnseenMentions: item.hasUnseenMentions, hasUnseenReactions: item.hasUnseenReactions,
                hasUnseenPollVotes: item.hasUnseenPollVotes, forumTopicData: item.forumTopicData,
                topForumTopicItems: item.topForumTopicItems, hasFailed: item.hasFailed,
                isContact: item.isContact, autoremoveTimeout: item.autoremoveTimeout,
                storyStats: item.storyStats, displayAsTopicList: item.displayAsTopicList,
                isPremiumRequiredToMessage: item.isPremiumRequiredToMessage,
                mediaDraftContentType: item.mediaDraftContentType
            )
        }
        let items = update.list.items.map(item)
        let additional = update.list.additionalItems.map { EngineChatList.AdditionalItem(item: item($0.item), promoInfo: $0.promoInfo) }
        let groups = update.list.groupItems.map { group -> EngineChatList.GroupItem in
            let message = group.topMessage.flatMap { visible($0) ? display($0) : nil }
            return EngineChatList.GroupItem(id: group.id, topMessage: message, items: group.items, unreadCount: group.unreadCount)
        }
        guard items != update.list.items || additional != update.list.additionalItems || groups != update.list.groupItems else { return update }
        return ChatListNodeViewUpdate(list: EngineChatList(items: items, groupItems: groups, additionalItems: additional,
            hasEarlier: update.list.hasEarlier, hasLater: update.list.hasLater, isLoading: update.list.isLoading), type: update.type, scrollPosition: update.scrollPosition)
    }
}

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
            count = min(messages.count, count + 8)
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
        // Render cached verdicts immediately, then wait off-thread for the full source messages.
        return .single(project(update)) |> then(prepare(update) |> mapToSignal { [self] _ in
            return loadMissing(update)
        })
    }

    private func sourceMessages(_ update: ChatListNodeViewUpdate) -> [Message] {
        let items = update.list.items + update.list.additionalItems.map(\.item)
        var sources: [MessageId: Message] = [:]
        for item in items {
            if case let .chatList(peerId) = item.id, let cached = recent[peerId], cached.top == item.messages {
                for message in cached.messages.prefix(cached.count) { sources[message.id] = message._asMessage() }
            }
            for message in item.messages { sources[message.id] = message._asMessage() }
        }
        for group in update.list.groupItems {
            if let message = group.topMessage { sources[message.id] = message._asMessage() }
        }
        return Array(sources.values)
    }

    private func prepare(_ update: ChatListNodeViewUpdate) -> Signal<Void, NoError> {
        let messages = sourceMessages(update)
        return Signal { [self] subscriber in
            session.prepare(messages, accountPeerId: context.account.peerId, scope: scope) {
                subscriber.putNext(()); subscriber.putCompletion()
            }
            return EmptyDisposable
        } |> deliverOn(queue)
    }

    private func loadMissing(_ update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
        let account = context.account.peerId
        let hidden = session.hiddenMessageIds(in: sourceMessages(update), accountPeerId: account, scope: scope)
        let items = update.list.items + update.list.additionalItems.map(\.item)
        let keywords = RGContentFilterState(accountPeerId: account)
        func visible(_ message: EngineMessage) -> Bool {
            !hidden.contains(message.id) && (keywords.isEmpty || !keywords.shouldHide(message: message))
        }
        var advanced = false
        for item in items {
            guard case let .chatList(peerId) = item.id, item.messages.allSatisfy({ !visible($0) }),
                  var cached = recent[peerId], cached.count < cached.messages.count,
                  !cached.messages.prefix(cached.count).contains(where: visible) else { continue }
            cached.advance(); recent[peerId] = cached; advanced = true
        }
        if advanced {
            return .single(project(update)) |> then(prepare(update) |> mapToSignal { [self] _ in loadMissing(update) })
        }
        var missing: [EnginePeer.Id: [EngineMessage]] = [:]
        for item in items {
            guard case let .chatList(peerId) = item.id, !item.messages.isEmpty, recent[peerId] == nil else { continue }
            // A captionless album top may require the caption carried by another local message.
            if item.messages.allSatisfy({ hidden.contains($0.id) }) || item.messages.contains(where: { $0.groupingKey != nil }) {
                missing[peerId] = item.messages
            }
        }
        // Bound retained history and keep each Postbox transaction small. Further chunks continue
        // in this signal; they do not depend on a new message/notification arriving to make progress.
        let batch = Array(missing.keys.sorted { $0.toInt64() < $1.toInt64() }.prefix(min(16, max(0, 128 - recent.count))))
        guard !batch.isEmpty else { return .single(project(update)) }
        return .single(project(update)) |> then(
            context.engine.messages.locallyStoredRecentMessages(peerIds: batch, limit: 50)
            |> deliverOn(queue)
            |> mapToSignal { [self] messages -> Signal<ChatListNodeViewUpdate, NoError> in
                for peerId in batch {
                    guard let top = missing[peerId], let newest = top.map(\.index).max() else { continue }
                    var cached = Recent(top: top, messages: (messages[peerId] ?? []).filter { $0.index <= newest }, count: 0)
                    cached.advance(); recent[peerId] = cached
                }
                return prepare(update) |> mapToSignal { [self] _ in loadMissing(update) }
            }
        )
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

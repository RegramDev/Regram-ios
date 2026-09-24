import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

// MARK: Regram
// A chat list item carries only the top message of its conversation, so when that message is hidden
// by the message filter or by a hidden sender the row would be left previewing something the user
// asked not to see. This walks back through locally stored history to find the newest message that
// is still visible and previews that instead.
//
// A hidden message should leave no other trace in the list either, so a substituted row is also
// ordered by the message it now previews, and a conversation whose only unread messages are hidden
// ones is marked read (see `markReadIfOnlyHiddenUnread`).

/// How far back to look for a visible message before giving up on a conversation. A chat where the
/// last N messages are all hidden simply shows no preview, which is the honest result.
private let rgPreviewLookbackLimit = 50

/// Upper bound on conversations looked up in a single pass. A broad filter rule can match the top
/// message of a great many chats at once, and each lookup is a history scan on the Postbox queue —
/// the same queue that opening a conversation needs. Capping keeps a wide rule from starving it;
/// beyond the cap the rows keep their original preview until a later pass picks them up.
private let rgPreviewLookupBatchLimit = 16

final class RGChatListPreviewSubstitution {
    private struct CacheEntry {
        /// The top message the lookup was performed for; a new top message invalidates the entry.
        let topMessageId: EngineMessage.Id
        let replacement: EngineMessage?
    }

    private let context: AccountContext
    /// Top messages change rarely, so caching by (peer, top message) makes the steady-state cost of
    /// this whole feature zero: no transaction runs unless something actually moved.
    private let cache = Atomic<[EnginePeer.Id: CacheEntry]>(value: [:])
    /// The newest top message each conversation was last seen with that was *not* hidden. A hidden
    /// message arriving on top of it leaves that as the newest visible one, so it can stand in at
    /// once while the lookup confirms it. Without it the row would first jump to the top of the list
    /// showing the hidden message, then drop back into place when the lookup finished.
    private let lastVisibleTopMessages = Atomic<[EnginePeer.Id: EngineMessage]>(value: [:])
    /// Top messages whose conversation was already marked read here, so one arrival is acted on once
    /// however many list updates carry it.
    private let markedReadTopMessageIds = Atomic<Set<EngineMessage.Id>>(value: Set())

    init(context: AccountContext) {
        self.context = context
    }

    func apply(to update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
        let filter = RGContentFilterState(accountPeerId: self.context.account.peerId)
        if filter.isEmpty {
            return .single(update)
        }

        // Only conversations whose entire preview is hidden need a replacement. Forum topic lists are
        // left alone: their rows share one peer, and both the cache and the lookup are per peer.
        var hiddenPreviewItems: [(peerId: EnginePeer.Id, topMessage: EngineMessage)] = []
        var visibleTopMessages: [EnginePeer.Id: EngineMessage] = [:]
        for item in update.list.items {
            guard case let .chatList(peerId) = item.id, let topMessage = item.messages.first else {
                continue
            }
            if item.messages.allSatisfy({ filter.shouldHide(message: $0) }) {
                hiddenPreviewItems.append((peerId, topMessage))
            } else {
                visibleTopMessages[peerId] = topMessage
            }
        }
        if !visibleTopMessages.isEmpty {
            let _ = self.lastVisibleTopMessages.modify { current in
                var current = current
                for (peerId, message) in visibleTopMessages {
                    current[peerId] = message
                }
                return current
            }
        }
        if hiddenPreviewItems.isEmpty {
            return .single(update)
        }

        let cached = self.cache.with { $0 }
        let missing = hiddenPreviewItems.filter { cached[$0.peerId]?.topMessageId != $0.topMessage.id }

        if missing.isEmpty {
            return .single(self.substituted(update: update, filter: filter, cache: cached))
        }

        // Stand-ins for the rows still waiting on a lookup; see `lastVisibleTopMessages`.
        let lastVisible = self.lastVisibleTopMessages.with { $0 }
        var provisional: [EnginePeer.Id: CacheEntry] = [:]
        for item in missing {
            if let message = lastVisible[item.peerId], message.index < item.topMessage.index {
                provisional[item.peerId] = CacheEntry(topMessageId: item.topMessage.id, replacement: message)
            }
        }
        func withProvisional(_ cache: [EnginePeer.Id: CacheEntry]) -> [EnginePeer.Id: CacheEntry] {
            var result = cache
            for (peerId, entry) in provisional where result[peerId]?.topMessageId != entry.topMessageId {
                result[peerId] = entry
            }
            return result
        }

        let peerIdsToLoad = Array(missing.prefix(rgPreviewLookupBatchLimit).map { $0.peerId })
        let topMessageIds = Dictionary(hiddenPreviewItems.map { ($0.peerId, $0.topMessage.id) }, uniquingKeysWith: { first, _ in first })

        // The un-looked-up update goes out first: rendering the list must never wait on Postbox.
        return .single(self.substituted(update: update, filter: filter, cache: withProvisional(cached)))
        |> then(
            self.context.engine.messages.locallyStoredRecentMessages(peerIds: peerIdsToLoad, limit: rgPreviewLookbackLimit)
            |> map { [weak self] recentMessages -> ChatListNodeViewUpdate in
                guard let self else {
                    return update
                }
                let updatedCache = self.cache.modify { current in
                    var current = current
                    for peerId in peerIdsToLoad {
                        guard let topMessageId = topMessageIds[peerId] else {
                            continue
                        }
                        let replacement = (recentMessages[peerId] ?? []).first(where: { !filter.shouldHide(message: $0) })
                        current[peerId] = CacheEntry(topMessageId: topMessageId, replacement: replacement)
                    }
                    return current
                }
                self.markReadIfOnlyHiddenUnread(update: update, peerIds: Set(peerIdsToLoad), recentMessages: recentMessages, filter: filter)
                return self.substituted(update: update, filter: filter, cache: withProvisional(updatedCache))
            }
        )
    }

    /// Marks a conversation read when every one of its unread messages is hidden. Otherwise a hidden
    /// arrival brings back the unread badge of a chat the user has already read, with nothing new to
    /// find in it — and the tab and app icon badges count it too, which no per-row adjustment of the
    /// counters could reach. It is what reading the chat would do anyway: the history view already
    /// advances the read marker past trailing hidden messages once the user reaches the bottom.
    ///
    /// Only when this can be verified: the unread messages have to fall within the lookback, and a
    /// chat the user explicitly marked unread is left alone.
    private func markReadIfOnlyHiddenUnread(update: ChatListNodeViewUpdate, peerIds: Set<EnginePeer.Id>, recentMessages: [EnginePeer.Id: [EngineMessage]], filter: RGContentFilterState) {
        for item in update.list.items {
            guard case let .chatList(peerId) = item.id, peerIds.contains(peerId), let topMessage = item.messages.first else {
                continue
            }
            guard let readCounters = item.readCounters, readCounters.count > 0, !readCounters.markedUnread else {
                continue
            }
            let unreadCount = Int(readCounters.count)
            let incoming = (recentMessages[peerId] ?? []).filter { $0.flags.contains(.Incoming) }
            guard incoming.count >= unreadCount, incoming.prefix(unreadCount).allSatisfy({ filter.shouldHide(message: $0) }) else {
                continue
            }
            var isNew = false
            let _ = self.markedReadTopMessageIds.modify { current in
                var current = current
                isNew = current.insert(topMessage.id).inserted
                return current
            }
            if isNew {
                let _ = self.context.engine.messages.applyMaxReadIndexInteractively(index: topMessage.index).startStandalone()
            }
        }
    }

    private func substituted(update: ChatListNodeViewUpdate, filter: RGContentFilterState, cache: [EnginePeer.Id: CacheEntry]) -> ChatListNodeViewUpdate {
        // The oldest unpinned row, as Postbox ordered it. Paging towards older conversations is
        // anchored on the first item of the list (ChatListNode.displayedItemRangeChanged), so a row
        // re-indexed below it would become the anchor and the next page would skip conversations.
        var pagingFloor: EngineMessage.Index?
        if update.list.hasEarlier {
            for item in update.list.items {
                if case let .chatList(index) = item.index, index.pinningIndex == nil {
                    pagingFloor = index.messageIndex
                    break
                }
            }
        }

        var items = update.list.items
        var didSubstitute = false
        var didReindex = false
        for index in 0 ..< items.count {
            let item = items[index]
            guard case let .chatList(peerId) = item.id, let topMessage = item.messages.first, item.messages.allSatisfy({ filter.shouldHide(message: $0) }) else {
                continue
            }
            // Without a completed lookup the row keeps its original preview rather than blanking.
            guard let entry = cache[peerId], entry.topMessageId == topMessage.id else {
                continue
            }
            didSubstitute = true

            // Postbox places the row by its top message, which is the hidden one, so left alone a row
            // previewing an old message sits above rows with newer ones. Place it by the message it
            // now previews instead — but only when the top message is what placed it: a pinned row,
            // or one placed by something newer such as a draft, keeps its index.
            var itemIndex = item.index
            if let replacement = entry.replacement, case let .chatList(chatListIndex) = item.index, chatListIndex.pinningIndex == nil, chatListIndex.messageIndex == topMessage.index {
                var messageIndex = replacement.index
                if let pagingFloor, messageIndex < pagingFloor {
                    messageIndex = EngineMessage.Index(id: messageIndex.id, timestamp: pagingFloor.timestamp)
                }
                itemIndex = .chatList(EngineChatList.Item.Index.ChatList(pinningIndex: nil, messageIndex: messageIndex))
                didReindex = true
            }

            items[index] = EngineChatList.Item(
                id: item.id,
                index: itemIndex,
                messages: entry.replacement.flatMap { [$0] } ?? [],
                readCounters: item.readCounters,
                isMuted: item.isMuted,
                draft: item.draft,
                threadData: item.threadData,
                renderedPeer: item.renderedPeer,
                presence: item.presence,
                hasUnseenMentions: item.hasUnseenMentions,
                hasUnseenReactions: item.hasUnseenReactions,
                hasUnseenPollVotes: item.hasUnseenPollVotes,
                forumTopicData: item.forumTopicData,
                topForumTopicItems: item.topForumTopicItems,
                hasFailed: item.hasFailed,
                isContact: item.isContact,
                autoremoveTimeout: item.autoremoveTimeout,
                storyStats: item.storyStats,
                displayAsTopicList: item.displayAsTopicList,
                isPremiumRequiredToMessage: item.isPremiumRequiredToMessage,
                mediaDraftContentType: item.mediaDraftContentType
            )
        }

        if !didSubstitute {
            return update
        }
        if didReindex {
            // The list is consumed in index order, and diffed against the previous one on that basis.
            items.sort(by: { $0.index < $1.index })
        }

        return ChatListNodeViewUpdate(
            list: EngineChatList(
                items: items,
                groupItems: update.list.groupItems,
                additionalItems: update.list.additionalItems,
                hasEarlier: update.list.hasEarlier,
                hasLater: update.list.hasLater,
                isLoading: update.list.isLoading
            ),
            type: update.type,
            scrollPosition: update.scrollPosition
        )
    }
}

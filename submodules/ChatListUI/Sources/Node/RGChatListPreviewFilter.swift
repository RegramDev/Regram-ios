import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

// MARK: Regram
// A chat list item carries only the top message of its conversation, so when that message is hidden
// by the message filter or by a hidden sender the row would be left previewing something the user
// asked not to see. This walks back through locally stored history to find the newest message that
// is still visible and previews that instead.

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

    init(context: AccountContext) {
        self.context = context
    }

    func apply(to update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
        let filter = RGContentFilterState(accountPeerId: self.context.account.peerId)
        if filter.isEmpty {
            return .single(update)
        }

        // Only conversations whose entire preview is hidden need a replacement.
        var hiddenPreviewItems: [(peerId: EnginePeer.Id, topMessageId: EngineMessage.Id)] = []
        for item in update.list.items {
            guard let topMessage = item.messages.first else {
                continue
            }
            if item.messages.allSatisfy({ filter.shouldHide(message: $0) }) {
                hiddenPreviewItems.append((item.renderedPeer.peerId, topMessage.id))
            }
        }
        if hiddenPreviewItems.isEmpty {
            return .single(update)
        }

        let cached = self.cache.with { $0 }
        let missing = hiddenPreviewItems.filter { cached[$0.peerId]?.topMessageId != $0.topMessageId }

        if missing.isEmpty {
            return .single(self.substituted(update: update, filter: filter, cache: cached))
        }

        let peerIdsToLoad = Array(missing.prefix(rgPreviewLookupBatchLimit).map { $0.peerId })
        let topMessageIds = Dictionary(hiddenPreviewItems.map { ($0.peerId, $0.topMessageId) }, uniquingKeysWith: { first, _ in first })

        // The un-substituted update goes out first: rendering the list must never wait on Postbox.
        return .single(self.substituted(update: update, filter: filter, cache: cached))
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
                return self.substituted(update: update, filter: filter, cache: updatedCache)
            }
        )
    }

    private func substituted(update: ChatListNodeViewUpdate, filter: RGContentFilterState, cache: [EnginePeer.Id: CacheEntry]) -> ChatListNodeViewUpdate {
        var items = update.list.items
        var didSubstitute = false
        for index in 0 ..< items.count {
            let item = items[index]
            guard let topMessage = item.messages.first, item.messages.allSatisfy({ filter.shouldHide(message: $0) }) else {
                continue
            }
            // Without a completed lookup the row keeps its original preview rather than blanking.
            guard let entry = cache[item.renderedPeer.peerId], entry.topMessageId == topMessage.id else {
                continue
            }
            didSubstitute = true
            items[index] = EngineChatList.Item(
                id: item.id,
                index: item.index,
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

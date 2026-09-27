import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import Postbox

final class RGChatListPreviewSubstitution {
    private let context: AccountContext
    private let queue = Queue(name: "regram.chat-list-projection")
    init(context: AccountContext) { self.context = context }

    func apply(to update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
        return self.context.account.filteredUnreadContext.state
        |> deliverOn(self.queue)
        |> map { [weak self] snapshot -> ChatListNodeViewUpdate in
            guard let self else { return update }
            let filter = RGContentFilterState(accountPeerId: self.context.account.peerId)
            guard !filter.isEmpty else { return update }
            // Do not blank a row while the account-wide projection is still being built. The first
            // snapshot is intentionally incomplete; waiting for the ready snapshot keeps the list
            // stable and lets the background scanner provide an exact replacement and unread count.
            guard snapshot.isReady else { return update }
            var items: [EngineChatList.Item] = []
            for item in update.list.items {
                let peerId = item.renderedPeer.peerId
                let threadId: Int64?
                switch item.id { case .chatList: threadId = nil; case let .forum(id): threadId = id }
                let key = RGFilteredChatKey(peerId: peerId, threadId: threadId)
                let result = snapshot.chats[key]
                let originalTop = item.messages.first
                let hiddenPreview = !item.messages.isEmpty && item.messages.allSatisfy { filter.shouldHide(message: $0) }
                let replacement = result?.topId == originalTop?.id ? result?.preview : nil
                let messages = hiddenPreview ? replacement.map { [$0] } ?? [] : item.messages
                let counters = item.readCounters.map { snapshot.counters(peerId: peerId, threadId: threadId, original: $0) }
                var index = item.index
                if hiddenPreview, let replacement, let originalTop {
                    switch item.index {
                    case let .chatList(value) where value.pinningIndex == nil && value.messageIndex == originalTop.index:
                        index = .chatList(EngineChatList.Item.Index.ChatList(pinningIndex: nil, messageIndex: replacement.index))
                    case let .forum(pinned, timestamp, threadId, namespace, id) where timestamp == originalTop.timestamp:
                        let _ = namespace; let _ = id
                        index = .forum(pinnedIndex: pinned, timestamp: replacement.timestamp, threadId: threadId, namespace: replacement.id.namespace, id: replacement.id.id)
                    default: break
                    }
                }
                items.append(EngineChatList.Item(id: item.id, index: index, messages: messages, readCounters: counters, isMuted: item.isMuted, draft: item.draft, threadData: item.threadData, renderedPeer: item.renderedPeer, presence: item.presence, hasUnseenMentions: item.hasUnseenMentions, hasUnseenReactions: item.hasUnseenReactions, hasUnseenPollVotes: item.hasUnseenPollVotes, forumTopicData: item.forumTopicData, topForumTopicItems: item.topForumTopicItems, hasFailed: item.hasFailed, isContact: item.isContact, autoremoveTimeout: item.autoremoveTimeout, storyStats: item.storyStats, displayAsTopicList: item.displayAsTopicList, isPremiumRequiredToMessage: item.isPremiumRequiredToMessage, mediaDraftContentType: item.mediaDraftContentType))
            }
            items.sort { $0.index < $1.index }
            let groups = update.list.groupItems.map { group -> EngineChatList.GroupItem in
                let groupId: PeerGroupId = group.id == .archive ? Namespaces.PeerGroup.archive : .root
                let removed = snapshot.removedChats(groupId: groupId)
                let top = group.topMessage.flatMap { message -> EngineMessage? in
                    if !filter.shouldHide(message: message) { return message }
                    guard let result = snapshot.chats[RGFilteredChatKey(peerId: message.id.peerId)], result.topId == message.id else {
                        return message
                    }
                    return result.preview
                }
                let groupItems = group.items.map { item -> EngineChatList.GroupItem.Item in
                    guard let result = snapshot.chats[RGFilteredChatKey(peerId: item.peer.peerId)] else {
                        return item
                    }
                    return EngineChatList.GroupItem.Item(peer: item.peer, isUnread: result.counters(result.original).isUnread)
                }
                return EngineChatList.GroupItem(id: group.id, topMessage: top, items: groupItems, unreadCount: max(0, group.unreadCount - removed))
            }
            return ChatListNodeViewUpdate(list: EngineChatList(items: items, groupItems: groups, additionalItems: update.list.additionalItems, hasEarlier: update.list.hasEarlier, hasLater: update.list.hasLater, isLoading: update.list.isLoading), type: update.type, scrollPosition: update.scrollPosition, paginationList: update.paginationList)
        }
    }
}

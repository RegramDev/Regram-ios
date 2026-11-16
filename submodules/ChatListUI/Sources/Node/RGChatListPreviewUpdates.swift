// MARK: Regram — filtering is a content update, never another initial load or scroll command.
import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox

func rgChatListPreviewUpdates() -> (Signal<ChatListNodeViewUpdate, NoError>) -> Signal<ChatListNodeViewUpdate, NoError> {
    return { signal in
        Signal { subscriber in
            var previous: EngineChatList?
            return signal.start(next: { update in
                if let previous, previous == update.list { return }
                let value = previous == nil ? update : ChatListNodeViewUpdate(list: update.list, type: .Generic, scrollPosition: nil)
                previous = update.list
                subscriber.putNext(value)
            }, completed: { subscriber.putCompletion() })
        }
    }
}

/// Paging/reconnection can temporarily return an empty, loading view. Keep the last rows until
/// that same filter has a result. A real empty result, or a different folder/filter, clears it.
final class RGChatListLoadingState {
    private var filter: ChatListFilter?
    private var loaded: EngineChatList?
    func apply(to update: ChatListNodeViewUpdate, filter: ChatListFilter?) -> ChatListNodeViewUpdate {
        if self.filter != filter { loaded = nil; self.filter = filter }
        if update.list.isLoading, update.list.items.isEmpty, update.list.additionalItems.isEmpty, let loaded {
            return ChatListNodeViewUpdate(list: loaded, type: .Generic, scrollPosition: nil)
        }
        if !update.list.items.isEmpty || !update.list.additionalItems.isEmpty { loaded = update.list }
        else if !update.list.isLoading { loaded = nil }
        return update
    }
}

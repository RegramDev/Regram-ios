import Foundation
import Postbox
import RGSimpleSettings

// MARK: Regram — pinned chats beyond the server's limit
//
// The server keeps at most `dialogs_pinned_limit` pins per list (5, or 10 with a real Premium
// subscription) and `messages.reorderPinnedDialogs` fails outright when asked for more. So the full
// order lives only in this device's chat list: the first N cloud chats of it are what the server is
// told, and the cloud chats after them are "overflow" pins that exist only here.
//
// The overflow set is remembered (RGSimpleSettings, per account and group) because every server
// path that writes pins — the pin synchronizer, `updatePinnedDialogs`, and the chat-list refetch on
// a hole or a state reset — replaces the local order with the server's. Without the set a local pin
// is indistinguishable from one another device unpinned, and is dropped.
//
// N is computed from the account's *real* Premium flag. Local Premium (RGLocalPremium) makes
// `Peer.isPremium` read true, which used to let the client pin 10 while the server accepted 5, so
// pins 6-10 vanished on the next sync; they are overflow pins now.
//
// Secret chats are never sent to the server and were already kept locally by upstream; they neither
// count toward N nor join the overflow set.

private func rgIsCloudPinnedItem(_ itemId: PinnedItemId) -> Bool {
    switch itemId {
    case let .peer(peerId):
        return peerId.namespace != Namespaces.Peer.SecretChat
    }
}

/// The number of cloud pins the server accepts in `groupId` for this account.
func rgServerPinnedChatLimit(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId) -> Int {
    var isPremium = false
    if let user = transaction.getPeer(accountPeerId) as? TelegramUser {
        isPremium = user.flags.contains(.isPremium)
    }
    let appConfiguration = transaction.getPreferencesEntry(key: PreferencesKeys.appConfiguration)?.get(AppConfiguration.self) ?? .defaultValue
    let limits = UserLimitsConfiguration(appConfiguration: appConfiguration, isPremium: isPremium)
    if case .root = groupId {
        return Int(limits.maxPinnedChatCount)
    } else {
        return Int(limits.maxArchivedPinnedChatCount)
    }
}

/// Splits a full local order into what the server is told (every secret chat plus the first
/// `limit` cloud chats, in order) and the local-only overflow.
func rgSplitPinnedItemIds(_ itemIds: [PinnedItemId], limit: Int) -> (server: [PinnedItemId], overflow: [PinnedItemId]) {
    var server: [PinnedItemId] = []
    var overflow: [PinnedItemId] = []
    var cloudCount = 0
    for itemId in itemIds {
        if !rgIsCloudPinnedItem(itemId) {
            server.append(itemId)
        } else if cloudCount < limit {
            server.append(itemId)
            cloudCount += 1
        } else {
            overflow.append(itemId)
        }
    }
    return (server, overflow)
}

/// Puts the `keep` items of `previousOrder` back into `order`, each right after the item it
/// followed before, so a server reorder does not move the local pins around.
func rgMergeLocalPinnedItemIds(_ order: [PinnedItemId], previousOrder: [PinnedItemId], keep: Set<PinnedItemId>) -> [PinnedItemId] {
    if keep.isEmpty {
        return order
    }
    var result = order
    var insertionIndex = 0
    for itemId in previousOrder {
        if let index = result.firstIndex(of: itemId) {
            insertionIndex = index + 1
        } else if keep.contains(itemId) {
            result.insert(itemId, at: insertionIndex)
            insertionIndex += 1
        }
    }
    return result
}

func rgLocalOverflowPinnedItemIds(accountPeerId: PeerId, groupId: PeerGroupId) -> Set<PinnedItemId> {
    let peerIds = RGSimpleSettings.shared.localOverflowPinnedPeerIds(accountPeerId: accountPeerId.toInt64(), groupId: groupId.rawValue)
    return Set(peerIds.map { PinnedItemId.peer(PeerId($0)) })
}

func rgSetLocalOverflowPinnedItemIds(_ itemIds: [PinnedItemId], accountPeerId: PeerId, groupId: PeerGroupId) {
    let peerIds = itemIds.map { itemId -> Int64 in
        switch itemId {
        case let .peer(peerId):
            return peerId.toInt64()
        }
    }
    RGSimpleSettings.shared.setLocalOverflowPinnedPeerIds(peerIds, accountPeerId: accountPeerId.toInt64(), groupId: groupId.rawValue)
}

/// Replaces the pins of `groupId` with an order the server sent, keeping this device's overflow
/// pins where they were. Used by every path that adopts the server's pinned list wholesale.
func rgSetServerPinnedItemIds(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId, itemIds: [PinnedItemId]) {
    let previousOrder = transaction.getPinnedItemIds(groupId: groupId)
    var keep = rgLocalOverflowPinnedItemIds(accountPeerId: accountPeerId, groupId: groupId)
    keep.formIntersection(previousOrder)
    keep.subtract(itemIds)
    let merged = rgMergeLocalPinnedItemIds(itemIds, previousOrder: previousOrder, keep: keep)
    transaction.setPinnedItemIds(groupId: groupId, itemIds: merged)
    rgSetLocalOverflowPinnedItemIds(merged.filter { keep.contains($0) }, accountPeerId: accountPeerId, groupId: groupId)
}

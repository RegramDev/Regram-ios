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
// The overflow order is remembered in account preferences (per account and group) because every server
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

// Account preferences commit with the pin order and are shared by the app and its extensions.
// Standard UserDefaults belongs to each process and cannot protect pins during an extension sync.
private struct RGLocalPinnedChatsState: Codable {
    let peerIds: [Int64]
}

private func rgLocalPinnedChatsKey(accountPeerId: PeerId, groupId: PeerGroupId) -> ValueBoxKey {
    return ValueBoxKey("regram.localOverflowPinned.\(accountPeerId.toInt64()).\(groupId.rawValue)")
}

private func rgLocalOverflowPinnedOrder(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId) -> [PinnedItemId] {
    let key = rgLocalPinnedChatsKey(accountPeerId: accountPeerId, groupId: groupId)
    if let state = transaction.getPreferencesEntry(key: key)?.get(RGLocalPinnedChatsState.self) {
        return state.peerIds.map { .peer(PeerId($0)) }
    }
    // Import the previous main-app preference when available. An empty extension domain must
    // not mark migration complete before the app has had a chance to read the old record.
    let peerIds = RGSimpleSettings.shared.localOverflowPinnedPeerIds(accountPeerId: accountPeerId.toInt64(), groupId: groupId.rawValue)
    let order = transaction.getPinnedItemIds(groupId: groupId)
    let limit = rgServerPinnedChatLimit(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId)
    let derived = rgSplitPinnedItemIds(order, limit: limit).overflow
    var seen = Set<PinnedItemId>()
    let imported = (derived + peerIds.map { .peer(PeerId($0)) }).filter { seen.insert($0).inserted }
    if !imported.isEmpty {
        rgSetLocalOverflowPinnedItemIds(transaction: transaction, imported, accountPeerId: accountPeerId, groupId: groupId)
    }
    return imported
}

func rgLocalOverflowPinnedItemIds(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId) -> Set<PinnedItemId> {
    return Set(rgLocalOverflowPinnedOrder(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId))
}

func rgSetLocalOverflowPinnedItemIds(transaction: Transaction, _ itemIds: [PinnedItemId], accountPeerId: PeerId, groupId: PeerGroupId) {
    var seen = Set<PinnedItemId>()
    let peerIds = itemIds.filter { rgIsCloudPinnedItem($0) && seen.insert($0).inserted }.map { itemId -> Int64 in
        switch itemId {
        case let .peer(peerId):
            return peerId.toInt64()
        }
    }
    let key = rgLocalPinnedChatsKey(accountPeerId: accountPeerId, groupId: groupId)
    // Keep an empty record after an explicit unpin so stale legacy preferences cannot revive it.
    transaction.updatePreferencesEntry(key: key, { _ in PreferencesEntry(RGLocalPinnedChatsState(peerIds: peerIds)) })
}

/// Seed shared, durable records before reset clears every cloud peer's chat-list inclusion.
/// Deriving overflow from the existing list also covers an extension that cannot read legacy defaults.
func rgPrepareLocalPinnedChatsForStateReset(transaction: Transaction, accountPeerId: PeerId) {
    for groupId: PeerGroupId in [.root, .group(1)] {
        let order = transaction.getPinnedItemIds(groupId: groupId)
        let limit = rgServerPinnedChatLimit(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId)
        var keep = rgLocalOverflowPinnedItemIds(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId)
        keep.formUnion(rgSplitPinnedItemIds(order, limit: limit).overflow)
        let stored = rgLocalOverflowPinnedOrder(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId)
        let preserved = order.filter { keep.contains($0) } + stored.filter { itemId in
            guard !order.contains(itemId) else { return false }
            if case let .peer(peerId) = itemId {
                return transaction.getPeerChatListInclusion(peerId).groupId == groupId
            }
            return false
        }
        rgSetLocalOverflowPinnedItemIds(transaction: transaction, preserved, accountPeerId: accountPeerId, groupId: groupId)
    }
}

/// Adopt server pins while preserving local overflow, including when a state reset erased the
/// visible list. The durable order is authoritative for local-only pins, not the temporary list.
func rgSetServerPinnedItemIds(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId, itemIds: [PinnedItemId], restoringState: Bool = false) {
    let previousOrder = transaction.getPinnedItemIds(groupId: groupId)
    let overflow = rgLocalOverflowPinnedOrder(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId).filter { itemId in
        switch itemId {
        case let .peer(peerId):
            guard transaction.getPeer(peerId) != nil else { return false }
            let currentGroup = transaction.getPeerChatListInclusion(peerId).groupId
            return currentGroup == groupId || (restoringState && currentGroup == nil)
        }
    }
    let overflowSet = Set(overflow)
    var keep = overflowSet
    // An archive refetch may see only its restored overflow. Without any common server
    // anchor those pins belong after the newly fetched prefix, not before it.
    if !previousOrder.contains(where: { itemIds.contains($0) }) {
        keep.removeAll()
    }
    // Secret chats have no server pin and must survive a wholesale cloud-list replacement too.
    keep.formUnion(previousOrder.filter { !rgIsCloudPinnedItem($0) })
    var merged = rgMergeLocalPinnedItemIds(itemIds, previousOrder: previousOrder, keep: keep)
    // After reset there may be no prior pin indices to anchor to. Append the persisted local order.
    merged.append(contentsOf: overflow.filter { !merged.contains($0) })
    transaction.setPinnedItemIds(groupId: groupId, itemIds: merged)
    rgSetLocalOverflowPinnedItemIds(transaction: transaction, merged.filter { overflowSet.contains($0) && !itemIds.contains($0) }, accountPeerId: accountPeerId, groupId: groupId)
}

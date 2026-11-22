import Foundation
import Postbox

private let rgPlacementKey = ValueBoxKey("regram.chatListPlacement.v1")
private struct RGChatPlacementState: Codable {
    struct Entry: Codable {
        var group: Int32
        var revision: Int64
        var pending: Bool?
    }
    var revision: Int64 = 0
    var entries: [String: Entry] = [:]
}

private func rgPlacementState(_ transaction: Transaction) -> RGChatPlacementState {
    transaction.getPreferencesEntry(key: rgPlacementKey)?.get(RGChatPlacementState.self) ?? RGChatPlacementState()
}

func rgRememberChatListPlacement(transaction: Transaction, peerId: PeerId, group: PeerGroupId? = nil, interactive: Bool = false) {
    guard let group = group ?? transaction.getPeerChatListInclusion(peerId).groupId else { return }
    var state = rgPlacementState(transaction)
    let key = String(peerId.toInt64())
    if !interactive && state.entries[key]?.group == group.rawValue { return }
    if interactive { state.revision += 1 }
    state.entries[key] = .init(group: group.rawValue, revision: interactive ? state.revision : (state.entries[key]?.revision ?? 0), pending: interactive ? true : state.entries[key]?.pending)
    transaction.updatePreferencesEntry(key: rgPlacementKey, { _ in PreferencesEntry(state) })
}

func rgRestoredChatListGroup(transaction: Transaction, peerId: PeerId) -> PeerGroupId {
    rgPlacementState(transaction).entries[String(peerId.toInt64())].map { PeerGroupId(rawValue: $0.group) } ?? .root
}

func rgChatListPlacementRevision(transaction: Transaction) -> Int64 {
    rgPlacementState(transaction).revision
}

func rgChatListPlacementChanged(transaction: Transaction, peerId: PeerId, after revision: Int64) -> Bool {
    (rgPlacementState(transaction).entries[String(peerId.toInt64())]?.revision ?? 0) > revision
}

func rgPendingChatListPlacements(transaction: Transaction) -> Set<PeerId> {
    Set(rgPlacementState(transaction).entries.compactMap { key, entry in
        entry.pending == true ? Int64(key).map(PeerId.init) : nil
    })
}

func rgResolveChatListGroup(transaction: Transaction, peerId: PeerId, serverGroup: PeerGroupId) -> PeerGroupId {
    let entry = rgPlacementState(transaction).entries[String(peerId.toInt64())]
    return entry?.pending == true ? PeerGroupId(rawValue: entry!.group) : serverGroup
}

func rgConfirmChatListPlacement(transaction: Transaction, peerId: PeerId, group: PeerGroupId) {
    var state = rgPlacementState(transaction)
    let key = String(peerId.toInt64())
    guard state.entries[key]?.pending == true, state.entries[key]?.group == group.rawValue else { return }
    state.entries[key]?.pending = false
    transaction.updatePreferencesEntry(key: rgPlacementKey, { _ in PreferencesEntry(state) })
}

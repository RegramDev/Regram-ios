#!/usr/bin/env python3
"""Compile production local-pin policy with account-free database and settings adapters."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
path = 'submodules/TelegramCore/Sources/Utils/RGLocalPinnedChats.swift'
source = subprocess.check_output(['git', 'show', 'bc99591dd9:' + path], cwd=ROOT, text=True) if args.baseline else (ROOT / path).read_text()
source = source.replace('import Postbox\n', '').replace('import RGSimpleSettings\n', '')
fixture = r'''
import Foundation
struct PeerId: Hashable, Codable {
    let value: Int64
    init(_ value: Int64) { self.value = value }
    var namespace: Int32 { value < 0 ? Namespaces.Peer.SecretChat : 0 }
    func toInt64() -> Int64 { value }
}
enum Namespaces { enum Peer { static let SecretChat: Int32 = 3 } }
enum PeerGroupId: Hashable {
    case root, group(Int32)
    var rawValue: Int32 { switch self { case .root: return 0; case let .group(value): return value } }
}
enum PinnedItemId: Hashable { case peer(PeerId) }
struct ValueBoxKey: Hashable { let value: String; init(_ value: String) { self.value = value } }
struct PreferencesEntry {
    let data: Data
    init?<T: Encodable>(_ value: T?) { guard let value else { return nil }; data = try! JSONEncoder().encode(value) }
    func get<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: data) }
}
struct AppConfiguration: Codable { static let defaultValue = AppConfiguration() }
enum PreferencesKeys { static let appConfiguration = ValueBoxKey("configuration") }
struct UserLimitsConfiguration {
    let maxPinnedChatCount: Int32
    let maxArchivedPinnedChatCount: Int32 = 5
    init(appConfiguration: AppConfiguration, isPremium: Bool) { maxPinnedChatCount = isPremium ? 10 : 5 }
}
struct UserFlags: OptionSet { let rawValue: Int; static let isPremium = UserFlags(rawValue: 1) }
class TelegramUser { var flags: UserFlags = [] }
enum Inclusion { case notIncluded, included(PeerGroupId)
    var groupId: PeerGroupId? { switch self { case .notIncluded: return nil; case let .included(groupId): return groupId } }
}
final class Transaction {
    var orders: [PeerGroupId: [PinnedItemId]] = [:]
    var inclusions: [PeerId: Inclusion] = [:]
    var preferences: [ValueBoxKey: PreferencesEntry] = [:]
    let account = TelegramUser()
    func getPeer(_ id: PeerId) -> Any? { account }
    func getPreferencesEntry(key: ValueBoxKey) -> PreferencesEntry? { preferences[key] }
    func updatePreferencesEntry(key: ValueBoxKey, _ f: (PreferencesEntry?) -> PreferencesEntry?) { preferences[key] = f(preferences[key]) }
    func getPinnedItemIds(groupId: PeerGroupId) -> [PinnedItemId] { orders[groupId] ?? [] }
    func setPinnedItemIds(groupId: PeerGroupId, itemIds: [PinnedItemId]) {
        orders[groupId] = itemIds
        for item in itemIds { if case let .peer(id) = item { inclusions[id] = .included(groupId) } }
    }
    func getPeerChatListInclusion(_ id: PeerId) -> Inclusion { inclusions[id] ?? .notIncluded }
    func clearCloudChatList() {
        for (group, order) in orders { orders[group] = order.filter { if case let .peer(id) = $0 { return id.namespace == Namespaces.Peer.SecretChat }; return false } }
        for id in inclusions.keys where id.namespace != Namespaces.Peer.SecretChat { inclusions[id] = .notIncluded }
    }
}
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var legacy: [String: [Int64]] = [:]
    func localOverflowPinnedPeerIds(accountPeerId: Int64, groupId: Int32) -> [Int64] { legacy["\(accountPeerId):\(groupId)"] ?? [] }
    func setLocalOverflowPinnedPeerIds(_ ids: [Int64], accountPeerId: Int64, groupId: Int32) { legacy["\(accountPeerId):\(groupId)"] = ids }
}
'''
# The same behavioral assertions also run against the pre-fix policy.
modern = 'private struct RGLocalPinnedChatsState' in source
adapter = '' if modern else r'''
func rgLocalOverflowPinnedItemIds(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId) -> Set<PinnedItemId> {
    rgLocalOverflowPinnedItemIds(accountPeerId: accountPeerId, groupId: groupId)
}
func rgSetLocalOverflowPinnedItemIds(transaction: Transaction, _ ids: [PinnedItemId], accountPeerId: PeerId, groupId: PeerGroupId) {
    rgSetLocalOverflowPinnedItemIds(ids, accountPeerId: accountPeerId, groupId: groupId)
}
func rgPrepareLocalPinnedChatsForStateReset(transaction: Transaction, accountPeerId: PeerId) {}
func rgSetServerPinnedItemIds(transaction: Transaction, accountPeerId: PeerId, groupId: PeerGroupId, itemIds: [PinnedItemId], restoringState: Bool) {
    rgSetServerPinnedItemIds(transaction: transaction, accountPeerId: accountPeerId, groupId: groupId, itemIds: itemIds)
}
'''
tests = r'''
@main enum Checks {
    static var failures: [String] = []
    static let account = PeerId(1000)
    static func pins(_ values: [Int64]) -> [PinnedItemId] { values.map { .peer(PeerId($0)) } }
    static func expect(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
    static func seed(_ transaction: Transaction, _ values: [Int64], group: PeerGroupId = .root) {
        let order = pins(values)
        transaction.setPinnedItemIds(groupId: group, itemIds: order)
        let limit = rgServerPinnedChatLimit(transaction: transaction, accountPeerId: account, groupId: group)
        rgSetLocalOverflowPinnedItemIds(transaction: transaction, rgSplitPinnedItemIds(order, limit: limit).overflow, accountPeerId: account, groupId: group)
    }
    static func main() {
        let transaction = Transaction()
        seed(transaction, [1,2,3,4,5,6,7,8])
        seed(transaction, [11,12,13,14,15,16,17], group: .group(1))
        rgPrepareLocalPinnedChatsForStateReset(transaction: transaction, accountPeerId: account)
        transaction.clearCloudChatList()
        rgSetServerPinnedItemIds(transaction: transaction, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]), restoringState: true)
        rgSetServerPinnedItemIds(transaction: transaction, accountPeerId: account, groupId: .group(1), itemIds: [], restoringState: true)
        expect(transaction.getPinnedItemIds(groupId: .root) == pins([1,2,3,4,5,6,7,8]), "State reset discarded ordinary-list overflow pins")
        expect(transaction.getPinnedItemIds(groupId: .group(1)) == pins([16,17]), "State reset discarded archive overflow before archive refetch")
        rgSetServerPinnedItemIds(transaction: transaction, accountPeerId: account, groupId: .group(1), itemIds: pins([11,12,13,14,15]))
        expect(transaction.getPinnedItemIds(groupId: .group(1)) == pins([11,12,13,14,15,16,17]), "Archive refetch failed to restore the full order")
        // Extensions have the account database but a different standard-preferences domain.
        RGSimpleSettings.shared.legacy = [:]
        expect(rgLocalOverflowPinnedItemIds(transaction: transaction, accountPeerId: account, groupId: .root) == Set(pins([6,7,8])), "Overflow not visible to another process")
        let reopened = Transaction(); reopened.preferences = transaction.preferences; reopened.orders = transaction.orders; reopened.inclusions = transaction.inclusions
        for _ in 0..<50 {
            rgSetServerPinnedItemIds(transaction: reopened, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]))
        }
        expect(reopened.getPinnedItemIds(groupId: .root) == pins([1,2,3,4,5,6,7,8]), "Repeated sync after process restart discarded overflow")
        let secrets = Transaction(); seed(secrets, [-1,1,2,3,4,5,6])
        rgSetServerPinnedItemIds(transaction: secrets, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]))
        expect(secrets.getPinnedItemIds(groupId: .root) == pins([-1,1,2,3,4,5,6]), "Server response dropped a pinned secret chat")
        let split = rgSplitPinnedItemIds(pins([-1,1,2,3,4,5,6]), limit: 5)
        expect(split.server == pins([-1,1,2,3,4,5]) && split.overflow == pins([6]), "Secret chats counted toward the cloud limit")
        let moved = Transaction(); seed(moved, [1,2,3,4,5,6,7])
        moved.inclusions[PeerId(6)] = .included(.group(1)); moved.inclusions[PeerId(7)] = .notIncluded
        rgSetServerPinnedItemIds(transaction: moved, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]))
        expect(moved.getPinnedItemIds(groupId: .root) == pins([1,2,3,4,5]), "Moved/deleted chats were resurrected by a server refresh")
        let localUnpin = Transaction(); seed(localUnpin, [1,2,3,4,5,6])
        localUnpin.setPinnedItemIds(groupId: .root, itemIds: pins([1,2,3,4,5]))
        rgSetLocalOverflowPinnedItemIds(transaction: localUnpin, [], accountPeerId: account, groupId: .root)
        RGSimpleSettings.shared.setLocalOverflowPinnedPeerIds([6], accountPeerId: account.toInt64(), groupId: 0)
        rgSetServerPinnedItemIds(transaction: localUnpin, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]))
        expect(localUnpin.getPinnedItemIds(groupId: .root) == pins([1,2,3,4,5]), "An explicit unpin was undone by stale legacy preferences")
        let migration = Transaction(); migration.setPinnedItemIds(groupId: .root, itemIds: pins([1,2,3,4,5,6]))
        expect(rgLocalOverflowPinnedItemIds(transaction: migration, accountPeerId: account, groupId: .root) == Set(pins([6])), "Legacy overflow did not migrate")
        RGSimpleSettings.shared.legacy = [:]
        expect(rgLocalOverflowPinnedItemIds(transaction: migration, accountPeerId: account, groupId: .root) == Set(pins([6])), "Migrated overflow was not persisted")
        let extensionFirst = Transaction(); extensionFirst.setPinnedItemIds(groupId: .root, itemIds: pins([1,2,3,4,5,6,7]))
        RGSimpleSettings.shared.legacy = [:]
        rgSetServerPinnedItemIds(transaction: extensionFirst, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]))
        expect(extensionFirst.getPinnedItemIds(groupId: .root) == pins([1,2,3,4,5,6,7]), "Extension-first migration discarded existing pins without main-app defaults")
        let noLegacyReset = Transaction(); noLegacyReset.setPinnedItemIds(groupId: .root, itemIds: pins([1,2,3,4,5,6,7]))
        rgPrepareLocalPinnedChatsForStateReset(transaction: noLegacyReset, accountPeerId: account)
        noLegacyReset.clearCloudChatList()
        rgSetServerPinnedItemIds(transaction: noLegacyReset, accountPeerId: account, groupId: .root, itemIds: pins([1,2,3,4,5]), restoringState: true)
        expect(noLegacyReset.getPinnedItemIds(groupId: .root) == pins([1,2,3,4,5,6,7]), "Reset migration needs to derive overflow before clearing inclusions")
        let premium = Transaction(); premium.account.flags = [.isPremium]; seed(premium, Array(1...12))
        expect(rgLocalOverflowPinnedItemIds(transaction: premium, accountPeerId: account, groupId: .root) == Set(pins([11,12])), "Real Premium must use its own server quota")
        let otherAccount = Transaction(); otherAccount.preferences = premium.preferences
        expect(rgLocalOverflowPinnedItemIds(transaction: otherAccount, accountPeerId: PeerId(2000), groupId: .root).isEmpty, "Accounts shared local pins")
        if !failures.isEmpty { for failure in failures { print("FAIL: " + failure) }; exit(1) }
        print("Local pin checks passed: ordinary/archive reset, 50 resyncs, process restart, legacy migration, account isolation, explicit unpin, moves/deletions, secret chats and real Premium quotas.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-local-pins-') as directory:
    work = Path(directory)
    swift = work / 'Checks.swift'; swift.write_text(fixture + source + adapter + tests)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True)

if not args.baseline:
    reset = (ROOT / 'submodules/TelegramCore/Sources/State/ResetState.swift').read_text()
    assert reset.index('rgPrepareLocalPinnedChatsForStateReset(') < reset.index('transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)')
    assert 'groupId: .root, itemIds: replacePinnedItemIds.map(PinnedItemId.peer), restoringState: true)' in reset
    assert 'groupId: .group(1), itemIds: transaction.getPinnedItemIds(groupId: .group(1)), restoringState: true)' in reset
    print('Reset integration passed: snapshot before invalidation, ordinary-list and archive restoration.')

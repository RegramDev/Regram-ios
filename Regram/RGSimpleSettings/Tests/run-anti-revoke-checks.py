#!/usr/bin/env python3
"""Exercise the production sender policy, deletion updates and both history pruning paths."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
core = root / 'submodules/TelegramCore/Sources'
policy = '\n'.join(line for line in (core / 'Utils/RGAntiRevoke.swift').read_text().splitlines() if not line.startswith('import '))
updates = (core / 'State/AccountStateManagementUtils.swift').read_text()
start = updates.index('            case let .DeleteMessagesWithGlobalIds(rgAllIds):')
end = updates.index('            case let .UpdateMinAvailableMessage(id):', start)
deletions = updates[start:end]
history = (core / 'State/HistoryViewStateValidation.swift').read_text()
prunings = []
offset = 0
while True:
    start = history.find('if !rgShouldRetainRevokedMessage(', offset)
    if start < 0:
        break
    end = history.index('}', start) + 1
    prunings.append(history[start:end])
    offset = end
assert len(prunings) == 2, 'Both regular and topic history reconciliation must apply sender exclusions'

fixture = r'''
import Foundation
struct PeerId: Hashable {
    let value: Int64
    var namespace: Int32 { value < 100 ? 0 : 1 }
    func toInt64() -> Int64 { value }
}
enum Namespaces { enum Peer { static let CloudUser: Int32 = 0 } }
struct MessageId: Hashable { let peerId: PeerId; let id: Int32 }
class Peer {}
final class TelegramUser: Peer {
    let botInfo: Int?
    init(bot: Bool) { botInfo = bot ? 1 : nil }
}
struct Flags: OptionSet {
    let rawValue: Int
    static let Incoming = Flags(rawValue: 1)
}
final class RGRevokedMessageAttribute {}
struct Message { let author: Peer?; var flags: Flags = .Incoming; var attributes: [Any] = [] }
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var antiRevoke = false
    var antiRevokeIgnoreBots = false
    var peers = Set<Int64>()
    var isAntiRevokeActive: Bool { antiRevoke || !peers.isEmpty }
    func isAntiRevokeEnabled(forPeer id: Int64) -> Bool { antiRevoke || peers.contains(id) }
}
typealias MediaResourceId = Int
struct Media {}
final class Transaction {
    var messages: [MessageId: Message] = [:]
    var peers: [PeerId: Peer] = [:]
    var marked = Set<MessageId>()
    var deleted = Set<MessageId>()
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func messageIdsForGlobalIds(_ ids: [Int32]) -> [MessageId] { messages.keys.filter { ids.contains($0.id) } }
    func deleteMessagesWithGlobalIds(_ ids: [Int32], forEachMedia: (Media) -> Void) { deleted.formUnion(messageIdsForGlobalIds(ids)) }
}
final class Signal { func start() -> Int { 0 } }
final class MediaBox { func removeCachedResources(_ ids: [Int], force: Bool) -> Signal { Signal() } }
final class Postbox { let mediaBox = MediaBox() }
func addMessageMediaResourceIdsToRemove(media: Media, resourceIds: inout [MediaResourceId]) {}
func rgMarkMessageRevoked(transaction: Transaction, id: MessageId) { transaction.marked.insert(id) }
func _internal_deleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], manualAddMessageThreadStatsDifference: ((Int, Int, Int) -> Void)? = nil) { transaction.deleted.formUnion(ids) }
func addMessageThreadStatsDifference(threadKey: Int, remove: Int, addedMessagePeer: Int?, addedMessageId: MessageId?, isOutgoing: Bool) {}
enum DeletedId { case global(Int32), messageId(MessageId) }
enum Operation { case DeleteMessagesWithGlobalIds([Int32]), DeleteMessages([MessageId]) }
POLICY
func apply(_ operation: Operation, transaction: Transaction) {
    let mediaBox = MediaBox()
    var deletedMessageIds: [DeletedId] = []
    switch operation {
        DELETIONS
    }
    _ = deletedMessageIds
}
func reconcile(transaction: Transaction, id: MessageId) {
    let postbox = Postbox()
    HISTORY
}
func reconcileTopic(transaction: Transaction, id: MessageId) {
    let postbox = Postbox()
    TOPIC_HISTORY
}
func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
@main enum Checks {
    static func main() {
        let settings = RGSimpleSettings.shared
        let human = TelegramUser(bot: false), bot = TelegramUser(bot: true)
        let humanId = MessageId(peerId: PeerId(value: 1), id: 11)
        let botId = MessageId(peerId: PeerId(value: 2), id: 12)
        let groupHumanId = MessageId(peerId: PeerId(value: 100), id: 13)
        let groupBotId = MessageId(peerId: PeerId(value: 100), id: 14)
        let unknownId = MessageId(peerId: PeerId(value: 100), id: 15)
        let missingAuthorBotId = MessageId(peerId: PeerId(value: 2), id: 16)
        let outgoingId = MessageId(peerId: PeerId(value: 2), id: 17)
        let inlineBotHumanId = MessageId(peerId: PeerId(value: 100), id: 18)
        func transaction() -> Transaction {
            let tx = Transaction()
            tx.messages = [humanId: Message(author: human), botId: Message(author: bot), groupHumanId: Message(author: human), groupBotId: Message(author: bot), unknownId: Message(author: nil), missingAuthorBotId: Message(author: nil), outgoingId: Message(author: nil, flags: []), inlineBotHumanId: Message(author: human)]
            tx.peers[botId.peerId] = bot; tx.peers[humanId.peerId] = human
            return tx
        }
        let globalIds = [humanId, botId, missingAuthorBotId, outgoingId]
        let groupIds = [groupHumanId, groupBotId, unknownId, inlineBotHumanId]
        for global in [false, true] {
            for ignoreBots in [false, true] {
                for scoped in [false, true] {
                    settings.antiRevoke = global; settings.antiRevokeIgnoreBots = ignoreBots
                    settings.peers = scoped ? [1, 100] : []
                    let tx = transaction()
                    apply(.DeleteMessagesWithGlobalIds(globalIds.map(\.id)), transaction: tx)
                    apply(.DeleteMessages(groupIds), transaction: tx)
                    for id in globalIds + groupIds {
                        let isBot = id == botId || id == groupBotId || id == missingAuthorBotId
                        let retained = (global || (scoped && [1, 100].contains(id.peerId.value))) && !(ignoreBots && isBot)
                        expect(tx.marked.contains(id) == retained, "Update retention must respect scope and the bot sender")
                        expect(tx.deleted.contains(id) == !retained, "Excluded messages must use normal deletion and resource cleanup")
                    }
                    for reconcile in [reconcile, reconcileTopic] {
                        let history = transaction()
                        for id in groupIds { reconcile(history, id) }
                        expect(history.deleted.contains(groupBotId) == (!global && !scoped || ignoreBots), "Both history paths must delete excluded bot messages")
                        expect(history.deleted.contains(groupHumanId) == (!global && !scoped), "Human messages must keep existing retention behavior")
                        expect(history.deleted.contains(unknownId) == (!global && !scoped), "Do not infer bot authors for anonymous messages")
                    }
                }
            }
        }
        settings.antiRevoke = true; settings.antiRevokeIgnoreBots = true
        let tx = transaction()
        expect(rgShouldRetainRevokedMessage(transaction: tx, id: outgoingId), "Outgoing messages to a bot are authored by the user")
        expect(rgShouldRetainRevokedMessage(transaction: tx, id: inlineBotHumanId), "Inline bot attribution does not make a human sender a bot")
        expect(rgShouldRetainRevokedMessage(transaction: tx, id: MessageId(peerId: PeerId(value: 100), id: 999)), "Unknown senders preserve existing behavior")
        tx.messages[groupBotId] = Message(author: bot, attributes: [RGRevokedMessageAttribute()])
        reconcile(transaction: tx, id: groupBotId); reconcileTopic(transaction: tx, id: groupBotId)
        expect(!tx.deleted.contains(groupBotId), "The new exclusion must not silently purge existing revoked-message records")
        print("Anti-revoke passed: all 8 scope/switch combinations, private/group updates, both history paths, missing authors, outgoing and inline-bot messages.")
    }
}
'''.replace('POLICY', policy).replace('DELETIONS', deletions).replace('TOPIC_HISTORY', prunings[1]).replace('HISTORY', prunings[0])
with tempfile.TemporaryDirectory(prefix='regram-anti-revoke-') as directory:
    folder = Path(directory)
    source = folder / 'Checks.swift'
    source.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(source), '-o', str(folder / 'checks')], check=True)
    subprocess.run([str(folder / 'checks')], check=True)

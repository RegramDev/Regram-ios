#!/usr/bin/env python3
"""Production TTL/retention codecs, timer guard and queue progression with isolated transactions."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()
timer = read('submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift')
helper = timer[timer.index('private final class ManagedAutoremoveMessageOperationsHelper'):timer.index('\nfunc managedAutoremoveMessageOperations(')]
a = timer.index('let rgIsSecretChat = message.id.peerId.namespace')
b = timer.index('                        if rgIsSecretChat || isRemove {', a)
guard = timer[a:b]
adapters = r'''
import Foundation
func postboxLog(_ value: String) {}
func mdb_cmp_memn(_ a: UnsafeRawPointer, _ al: Int, _ b: UnsafeRawPointer, _ bl: Int) -> Int32 { let v = memcmp(a, b, min(al, bl)); return v != 0 ? v : (al == bl ? 0 : (al < bl ? -1 : 1)) }
public struct PeerId: Hashable { let namespace: Int32; let value: Int64; func toInt64() -> Int64 { value } }
public struct MessageId: Hashable { public typealias Namespace = Int32; let peerId: PeerId; let namespace: Int32; let id: Int32 }
public protocol MessageAttribute: PostboxCoding { var automaticTimestampBasedAttribute: (UInt16, Int32)? { get } }
public extension MessageAttribute { var automaticTimestampBasedAttribute: (UInt16, Int32)? { nil } }
public struct Message {
 let id: MessageId; let timestamp: Int32; let attributes: [MessageAttribute]; let media: [String]
 var flags: Int { 0 }; var tags: Int { 0 }; var globalTags: Int { 0 }; var localTags: Int { 0 }
 var globallyUniqueId: Int64? { nil }; var groupingKey: Int64? { nil }; var threadId: Int64? { nil }; var forwardInfo: Int? { nil }; var author: Author? { nil }; var text: String { "retained text" }
 init(id: MessageId, timestamp: Int32, attributes: [MessageAttribute], media: [String]) { self.id = id; self.timestamp = timestamp; self.attributes = attributes; self.media = media }
 init(id: MessageId, customStableId: Int?, globallyUniqueId: Int64?, groupingKey: Int64?, threadId: Int64?, timestamp: Int32, flags: StoreMessageFlags, tags: Int, globalTags: Int, localTags: Int, forwardInfo: StoreMessageForwardInfo?, authorId: PeerId?, text: String, attributes: [MessageAttribute], media: [String]) { self.init(id: id, timestamp: timestamp, attributes: attributes, media: media) }
}
public struct Author { let id: PeerId }
public struct EngineMessage { let attributes: [MessageAttribute] }
public typealias StoreMessage = Message
public struct StoreMessageFlags { init(_ value: Int) {} }
public struct StoreMessageForwardInfo { init(_ value: Int) {} }
public enum PostboxUpdateMessage { case skip, update(StoreMessage) }
final class RGSimpleSettings {
 static let shared = RGSimpleSettings(); var antiRevoke = false; var protectedPeers: Set<Int64> = []; var antiAutoDelete = false; var antiSelfDestruct = false
 func isAntiRevokeEnabled(forPeer id: Int64) -> Bool { antiRevoke || protectedPeers.contains(id) }
}
enum Namespaces { enum Peer { static let SecretChat: Int32 = 3 } }
protocol Disposable { func dispose() }
final class MetaDisposable: Disposable { func dispose() {} }
public struct TimestampBasedMessageAttributesEntry { let messageId: MessageId; let tag: UInt16; let index: Int }
enum TimestampBasedMessageAttributesOperation { case add(TimestampBasedMessageAttributesEntry), remove(TimestampBasedMessageAttributesEntry) }
final class TimestampTable { var entries: [TimestampBasedMessageAttributesEntry] = []; func head(tag: UInt16) -> TimestampBasedMessageAttributesEntry? { entries.filter { $0.tag == tag }.min { $0.index < $1.index } } }
final class PostboxImpl { let timestampBasedMessageAttributesTable = TimestampTable() }
final class Transaction {
 var messages: [MessageId: Message] = [:]; var consumed: [MessageId] = []; var processed: [MessageId] = []; var queriedBounds: (Int32, Int32)?
 func getMessage(_ id: MessageId) -> Message? { messages[id] }
 func updateMessage(_ id: MessageId, update: (Message) -> PostboxUpdateMessage) {
  guard let old = messages[id] else { return }
  if case let .update(value) = update(old) { messages[id] = value }
 }
 func clearTimestampBasedAttribute(id: MessageId, tag: UInt16) { consumed.append(id) }
 func rgMessageIdsInRange(peerId: PeerId, namespace: Int32, minId: Int32, maxId: Int32) -> [MessageId] {
  queriedBounds = (minId, maxId)
  return messages.keys.filter { $0.peerId == peerId && $0.namespace == namespace && (minId...maxId).contains($0.id) }
 }
}
'''
production = ''
for file in ['SyncCore/SyncCore_AutoremoveTimeoutMessageAttribute.swift', 'SyncCore/SyncCore_RGRevokedMessageAttribute.swift', 'Utils/RGMessageRetention.swift']:
    content = read('submodules/TelegramCore/Sources/' + file)
    if file.endswith('SyncCore_AutoremoveTimeoutMessageAttribute.swift'):
        content = content.split('public extension Message {')[0]
    production += '\n'.join(line for line in content.splitlines() if not line.startswith('import ')) + '\n'
production += helper + read('submodules/Postbox/Sources/TimestampBasedMessageAttributesView.swift')
production += '\nfunc runDue(transaction: Transaction, entry: TimestampBasedMessageAttributesEntry, tag: UInt16) {\n guard let message = transaction.getMessage(entry.messageId) else { return }\n' + guard + '\ntransaction.processed.append(entry.messageId)\n}\n'
tests = r'''
@main enum Checks {
 static func main() {
  let cloud = PeerId(namespace: 0, value: 1), secret = PeerId(namespace: 3, value: 2)
  for tag: UInt16 in [0, 1] {
   let one = MessageId(peerId: cloud, namespace: 0, id: 1), two = MessageId(peerId: secret, namespace: 0, id: 2)
   let first = TimestampBasedMessageAttributesEntry(messageId: one, tag: tag, index: 10), second = TimestampBasedMessageAttributesEntry(messageId: two, tag: tag, index: 20)
   let db = PostboxImpl(), transaction = Transaction()
   db.timestampBasedMessageAttributesTable.entries = [first, second]
   let ttl: MessageAttribute = tag == 0 ? AutoremoveTimeoutMessageAttribute(timeout: 10, countdownBeginTime: 1) : AutoclearTimeoutMessageAttribute(timeout: 10, countdownBeginTime: 1)
   transaction.messages[one] = Message(id: one, timestamp: 1, attributes: [ttl], media: ["cached-media"])
   transaction.messages[two] = Message(id: two, timestamp: 1, attributes: [ttl], media: [])
   let view = MutableTimestampBasedMessageAttributesView(postbox: db, tag: tag), queue = ManagedAutoremoveMessageOperationsHelper()
   precondition(queue.update(view.head).beginOperations.count == 1)
   RGSimpleSettings.shared.antiAutoDelete = true; RGSimpleSettings.shared.antiSelfDestruct = false
   runDue(transaction: transaction, entry: first, tag: tag)
   let kept = transaction.messages[one]!
   precondition(kept.media == ["cached-media"] && kept.attributes[0].automaticTimestampBasedAttribute == nil && transaction.consumed == [one])
   // Persist/reopen the consumed TTL. Old versions without the new field still run normally.
   let encoder = PostboxEncoder(); kept.attributes[0].encode(encoder)
   let decoder = PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData()))
   let reopened: MessageAttribute = tag == 0 ? AutoremoveTimeoutMessageAttribute(decoder: decoder) : AutoclearTimeoutMessageAttribute(decoder: decoder)
   precondition(reopened.automaticTimestampBasedAttribute == nil)
   let old = PostboxEncoder(); old.encodeInt32(10, forKey: "t"); old.encodeInt32(1, forKey: "c")
   let oldDecoder = PostboxDecoder(buffer: MemoryBuffer(data: old.makeData()))
   let legacy: MessageAttribute = tag == 0 ? AutoremoveTimeoutMessageAttribute(decoder: oldDecoder) : AutoclearTimeoutMessageAttribute(decoder: oldDecoder)
   precondition(legacy.automaticTimestampBasedAttribute?.0 == tag && legacy.automaticTimestampBasedAttribute?.1 == 11)
   db.timestampBasedMessageAttributesTable.entries.removeFirst()
   precondition(view.replay(postbox: db, operations: [.remove(first)]))
   precondition(queue.update(view.head).beginOperations.first?.0.messageId == two)
   runDue(transaction: transaction, entry: second, tag: tag)
   precondition(transaction.processed == [two], "An unprotected secret message behind the protected head must run")
   RGSimpleSettings.shared.antiAutoDelete = false
   precondition(reopened.automaticTimestampBasedAttribute == nil)
  }
  let transaction = Transaction()
  for id: Int32 in 1...4 {
   let key = MessageId(peerId: cloud, namespace: 0, id: id)
   transaction.messages[key] = Message(id: key, timestamp: 1, attributes: [], media: ["media"])
  }
  RGSimpleSettings.shared.protectedPeers = [1]
  precondition(rgRetainDeletedMessageRange(transaction: transaction, peerId: cloud, namespace: 0, maxId: 3))
  precondition(transaction.queriedBounds?.0 == 1 && transaction.queriedBounds?.1 == 3 && transaction.messages.count == 4)
  precondition(transaction.messages.values.filter(\.rgIsRevoked).count == 3)
  let id = MessageId(peerId: cloud, namespace: 0, id: 4)
  rgMarkMessageRevoked(transaction: transaction, id: id, reason: .unavailable)
  precondition(!transaction.messages[id]!.rgIsRevoked)
  let unavailable = transaction.messages[id]!.attributes.first as! RGRevokedMessageAttribute
  let encoder = PostboxEncoder(); unavailable.encode(encoder)
  precondition(RGRevokedMessageAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData()))).reason == .unavailable)
  rgMarkMessageRevoked(transaction: transaction, id: id)
  rgMarkMessageRevoked(transaction: transaction, id: id, reason: .unavailable)
  precondition(transaction.messages[id]!.rgIsRevoked, "An explicit deletion can upgrade an unavailable record, never downgrade it")
  RGSimpleSettings.shared.protectedPeers = []
  precondition(!rgRetainDeletedMessageRange(transaction: transaction, peerId: cloud, namespace: 0, maxId: 4))
  print("Retention checks passed: both timer queues advance, preserved TTL survives coding, legacy timers remain active, indexed ranges keep media, and unavailable records differ from confirmed deletion.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-retention-') as temporary:
    work = Path(temporary)
    header = root / 'submodules/MurMurHash32/PublicHeaders/MurMurHash32/MurMurHash32.h'
    (work / 'module.modulemap').write_text('module MurMurHash32 { header "' + str(header) + '" export * }\n')
    subprocess.run(['xcrun', 'clang', '-dynamiclib', '-fobjc-arc', '-framework', 'Foundation', '-I', str(root / 'submodules/MurMurHash32/PublicHeaders'), str(root / 'submodules/MurMurHash32/Sources/MurMurHash32.m'), '-o', str(work / 'libMurMurHash32.dylib')], check=True)
    (work / 'Checks.swift').write_text(adapters + production + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-I', str(work), '-L', str(work), '-lMurMurHash32', '-Xlinker', '-rpath', '-Xlinker', str(work), str(root / 'submodules/Postbox/Sources/Coding.swift'), *map(str, sorted((root / 'submodules/Postbox/Sources/Utils').rglob('*.swift'))), str(work / 'Checks.swift'), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True, timeout=30)

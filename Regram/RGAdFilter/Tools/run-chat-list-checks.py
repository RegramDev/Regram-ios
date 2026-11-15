#!/usr/bin/env python3
"""Exercise production preview + bridge using real SwiftSignalKit and isolated message storage.

No account files or model predictions are used as ground truth. The fixture ads use an
existing precise policy rule so these checks isolate integration, cancellation and albums.
"""
from pathlib import Path
import runpy, subprocess, tempfile
root = Path(__file__).resolve().parents[3]
bridge = runpy.run_path(str(Path(__file__).with_name('run-bridge-checks.py')))
adapters = bridge['adapters'].replace('    let account: Account\n', '    let account: Account\n    let engine = Engine()\n')
# Include every production Item field, with opaque scalar metadata, so dropping any field fails.
item_source = (root/'submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift').read_text()
fields = item_source.split('        public let id: Id\n', 1)[1].split('        public init(', 1)[0]
import re
metadata = re.findall(r'public let (\w+):', fields)
metadata = [x for x in metadata if x not in ('index', 'messages')]
fields = '\n'.join('let '+x+': Int' for x in metadata)
initializer = ', '.join(x+': Int' for x in metadata)
assign = '; '.join('self.'+x+' = '+x for x in metadata)
args = ', '.join(f'{x}: {i+100}' for i,x in enumerate(metadata))
extras = r'''
struct EnginePeer { typealias Id = PeerId }
struct EngineMessage: Equatable {
    typealias Id = MessageId
    let message: Message
    init(_ message: Message) { self.message = message }
    var id: Id { message.id }
    var index: Int32 { id.id }
    var groupingKey: Int64? { message.groupingKey }
    func _asMessage() -> Message { message }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.message.stableVersion == b.message.stableVersion && a.message.text == b.message.text }
}
struct RGContentFilterState {
    static var keyword: String? = nil
    init(accountPeerId: PeerId) {}
    var isEmpty: Bool { Self.keyword == nil }
    func shouldHide(message: EngineMessage) -> Bool { Self.keyword.map { message.message.text.contains($0) } ?? false }
}
struct ChatListNodeViewUpdate { let list: EngineChatList; let type: Int; let scrollPosition: Int? }
struct EngineChatList: Equatable {
    struct Item: Equatable {
        enum Id: Hashable { case chatList(PeerId), forum(Int64) }
        let id: Id; let index: Int; let messages: [EngineMessage]
        METADATA_FIELDS
        init(id: Id, index: Int, messages: [EngineMessage], METADATA_INIT) {
            self.id = id; self.index = index; self.messages = messages; METADATA_ASSIGN
        }
    }
    struct AdditionalItem: Equatable { let item: Item; let promoInfo: Int }
    struct GroupItem: Equatable { let id: Int; let topMessage: EngineMessage?; let items: [Int]; let unreadCount: Int }
    let items: [Item]; let groupItems: [GroupItem]; let additionalItems: [AdditionalItem]
    let hasEarlier: Bool; let hasLater: Bool; let isLoading: Bool
}
final class Engine {
    let messages = Storage()
    final class Storage {
        var history: [PeerId: [EngineMessage]] = [:]
        var queries: [[PeerId]] = []
        var delayed = false
        func locallyStoredRecentMessages(peerIds: [PeerId], limit: Int) -> Signal<[PeerId: [EngineMessage]], NoError> {
            precondition(peerIds.count <= 16 && limit <= 50)
            queries.append(peerIds)
            let result = Dictionary(uniqueKeysWithValues: peerIds.map { ($0, Array((history[$0] ?? []).prefix(limit))) })
            return Signal { subscriber in
                let emit = { subscriber.putNext(result); subscriber.putCompletion() }
                if self.delayed { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: emit) } else { emit() }
                return EmptyDisposable
            }
        }
    }
}
'''.replace('METADATA_FIELDS',fields).replace('METADATA_INIT',initializer).replace('METADATA_ASSIGN',assign)
checks = r'''
@main enum Checks {
    static func spin(_ condition: () -> Bool) {
        let until = Date().addingTimeInterval(20)
        while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(condition(), "asynchronous preview did not complete")
    }
    static func main() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let context = AccountContext(path.path), session = RGAdFilterSession.get(context), account = context.account.peerId
        let helper = RGChatListAdPreview(context: context, queue: .mainQueue())
        let ad = "0充值，免费体验，中奖可提现 → @promotion_user"
        func message(_ id: Int32, _ text: String, peer: Int64 = 99, image: Bool = false, album: Int64? = nil, version: UInt32 = 1) -> Message {
            var entities: [MessageTextEntity] = []
            let range = (text as NSString).range(of: "@promotion_user")
            if range.location != NSNotFound { entities.append(MessageTextEntity(range: range.location..<NSMaxRange(range), type: .Mention)) }
            let value = Message(id: id, text: text, attributes: [TextEntitiesMessageAttribute(entities: entities)], media: image ? [TelegramMediaImage()] : [], version: version, peerValue: peer)
            value.groupingKey = album
            return value
        }
        func item(_ messages: [Message], index: Int = 777) -> EngineChatList.Item {
            EngineChatList.Item(id: .chatList(messages.first!.id.peerId), index: index, messages: messages.map(EngineMessage.init), METADATA_ARGS)
        }
        func update(_ items: [EngineChatList.Item]) -> ChatListNodeViewUpdate {
            ChatListNodeViewUpdate(list: EngineChatList(items: items, groupItems: [], additionalItems: [], hasEarlier: true, hasLater: false, isLoading: false), type: 2, scrollPosition: 19)
        }
        func apply(_ update: ChatListNodeViewUpdate, using helper: RGChatListAdPreview? = nil) -> ChatListNodeViewUpdate {
            var last: ChatListNodeViewUpdate?, done = false
            let disposable = (helper ?? ChecksHelper.value!).apply(to: update).start(next: { last = $0 }, completed: { done = true })
            spin { done }; disposable.dispose(); return last!
        }
        ChecksHelper.value = helper
        let mixed = message(9, "正常电影简介👋\n" + ad, image: true)
        let original = update([item([mixed])]), cleaned = apply(original)
        let body = cleaned.list.items[0].messages[0].message
        precondition(body.text == "正常电影简介👋\n" && body.media.count == 1 && body.textEntitiesAttribute!.entities.isEmpty)
        precondition(rgAdOriginalMessage(body) === mixed)
        precondition(cleaned.type == original.type && cleaned.scrollPosition == original.scrollPosition && cleaned.list.hasEarlier)
        let expected = EngineChatList.Item(id: original.list.items[0].id, index: 777, messages: cleaned.list.items[0].messages, METADATA_ARGS)
        precondition(cleaned.list.items[0] == expected, "preview changed metadata or unread/draft state")
        let pure = message(10, ad, image: true), normal = message(8, "正常消息", image: true)
        context.engine.messages.history[normal.id.peerId] = [EngineMessage(message(11, "未来消息")), EngineMessage(pure), EngineMessage(normal)]
        let fallback = apply(update([item([pure])]))
        precondition(fallback.list.items[0].messages.map(\.id) == [normal.id] && fallback.list.items[0].index == 777)
        let queries = context.engine.messages.queries.count
        _ = apply(update([item([pure])]))
        precondition(context.engine.messages.queries.count == queries, "stable list repeats history lookup")
        let edited = message(10, "编辑为正常内容", image: true, version: 2)
        precondition(apply(update([item([edited])])).list.items[0].messages[0].message.text == edited.text)
        let noHistory = message(12, ad, peer: 101, image: true)
        precondition(apply(update([item([noHistory])])).list.items[0].messages.isEmpty, "pure ad leaks image or notice")
        let topic = EngineChatList.Item(id: .forum(7), index: 901, messages: [EngineMessage(pure)], METADATA_ARGS)
        let surfaces = ChatListNodeViewUpdate(list: EngineChatList(items: [topic], groupItems: [EngineChatList.GroupItem(id: 1, topMessage: EngineMessage(pure), items: [8], unreadCount: 99)], additionalItems: [EngineChatList.AdditionalItem(item: item([pure]), promoInfo: 42)], hasEarlier: false, hasLater: true, isLoading: false), type: 3, scrollPosition: nil)
        let projectedSurfaces = apply(surfaces)
        precondition(projectedSurfaces.list.items[0].messages.isEmpty, "topic preview kept a pure ad")
        precondition(projectedSurfaces.list.items[0].index == 901 && projectedSurfaces.list.hasLater)
        precondition(projectedSurfaces.list.groupItems[0].topMessage == nil && projectedSurfaces.list.groupItems[0].unreadCount == 99)
        precondition(projectedSurfaces.list.additionalItems[0].promoInfo == 42 && projectedSurfaces.list.additionalItems[0].item.messages.map(\.id) == [normal.id])
        RGSimpleSettings.shared.adFiltering = false
        precondition(apply(update([item([pure])])).list.items[0].messages[0].message === pure)
        RGSimpleSettings.shared.adFiltering = nil
        let caption = message(30, ad, image: true, album: 55), photo = message(31, "", image: true, album: 55)
        let separate = message(29, "", image: true)
        context.engine.messages.history[photo.id.peerId] = [EngineMessage(photo), EngineMessage(caption), EngineMessage(separate)]
        precondition(apply(update([item([photo])])).list.items[0].messages.map(\.id) == [separate.id], "advertising album picture survived")
        let otherCaption = message(32, "正常相册说明", image: true, album: 55)
        var ready = false
        session.prepare([caption, photo, otherCaption], accountPeerId: account) { DispatchQueue.main.async { ready = true } }
        spin { ready }
        precondition(!session.hiddenMessageIds(in: [caption, photo, otherCaption], accountPeerId: account).contains(photo.id), "mixed album lost normal pictures")
        ready = false
        session.perform(changes: true, { store in
            var sample = try rgAdSampleDraft(photo, store: store); sample.mediaLabel = .normal; try store.save(sample)
        }) { _ in ready = true }; spin { ready }
        ready = false
        session.prepare([caption, photo], accountPeerId: account) { DispatchQueue.main.async { ready = true } }; spin { ready }
        precondition(!session.hiddenMessageIds(in: [caption, photo], accountPeerId: account).contains(photo.id), "reviewed normal media overridden")
        let otherPhoto = message(33, "", image: true, album: 55)
        ready = false
        session.prepare([caption, otherPhoto], accountPeerId: account) { DispatchQueue.main.async { ready = true } }; spin { ready }
        precondition(session.hiddenMessageIds(in: [caption, otherPhoto], accountPeerId: account).contains(otherPhoto.id), "another image inherited a normal media review")
        let markedPhoto = message(34, "", image: true), unrelatedPhoto = message(35, "", image: true)
        ready = false
        session.perform(changes: true, { store in
            var sample = try rgAdSampleDraft(markedPhoto, store: store); sample.mediaLabel = .ad; try store.save(sample)
        }) { _ in ready = true }; spin { ready }
        ready = false
        session.prepare([markedPhoto, unrelatedPhoto], accountPeerId: account) { DispatchQueue.main.async { ready = true } }; spin { ready }
        precondition(session.shouldHide(markedPhoto, accountPeerId: account))
        precondition(!session.shouldHide(unrelatedPhoto, accountPeerId: account), "media-only review hid an unrelated image")
        // Two list nodes must not cancel each other's worker batches.
        let second = RGChatListAdPreview(context: context, queue: .mainQueue())
        var firstDone = false, secondDone = false
        let a = helper.apply(to: update([item([mixed])])).start(completed: { firstDone = true })
        let b = second.apply(to: update([item([noHistory])])).start(completed: { secondDone = true })
        spin { firstDone && secondDone }; a.dispose(); b.dispose()
        // More than a transaction's 16 peers must complete without further notifications.
        let many = (200..<234).map { item([message(40, ad, peer: Int64($0), image: true)]) }
        precondition(apply(update(many)).list.items.allSatisfy { $0.messages.isEmpty })
        // Older fallback candidates are classified progressively, never exposed unprepared.
        let longAds = (90...110).reversed().map { message(Int32($0), ad, peer: 700, image: true) }
        let deepNormal = message(80, "更早的正常消息", peer: 700)
        context.engine.messages.history[deepNormal.id.peerId] = (longAds + [deepNormal]).map(EngineMessage.init)
        var deepDone = false, deepResult: ChatListNodeViewUpdate?
        let deep = helper.apply(to: update([item([longAds[0]])])).start(next: { value in
            for message in value.list.items[0].messages where message.id != longAds[0].id {
                precondition(message.id == deepNormal.id, "unprepared older advertisement flashed in preview")
            }
            deepResult = value
        }, completed: { deepDone = true })
        spin { deepDone }; deep.dispose()
        precondition(deepResult!.list.items[0].messages.map(\.id) == [deepNormal.id])
        context.engine.messages.delayed = true
        var completedCancelled = false
        let cancelled = helper.apply(to: update([item([message(50, ad, peer: 500)])])).start(completed: { completedCancelled = true })
        cancelled.dispose()
        _ = apply(update([item([edited])]))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(!completedCancelled, "disposed preview delivered a late completion")
        // Ordinary cloud groups are eligible; private/outgoing messages remain unchanged.
        let group = message(60, ad, peer: 601); group.peers[group.id.peerId] = TelegramGroup()
        precondition(apply(update([item([group])])).list.items[0].messages.isEmpty)
        let direct = message(61, ad); direct.peers[direct.id.peerId] = Peer()
        precondition(apply(update([item([direct])])).list.items[0].messages[0].message === direct)
        let outgoing = message(62, ad); outgoing.incoming = false
        precondition(apply(update([item([outgoing])])).list.items[0].messages[0].message === outgoing)
        print("Chat list checks passed: original preservation, mixed captions/entities/media, pure-ad fallback, no-history blank, edits, settings, album inheritance and veto, two concurrent lists, progressive batches, cancellation, group eligibility and unchanged metadata.")
    }
}
enum ChecksHelper { static var value: RGChatListAdPreview? }
'''.replace('METADATA_ARGS',args)
helper = (root/'submodules/ChatListUI/Sources/Node/RGChatListAdPreview.swift').read_text()
helper = '\n'.join(x for x in helper.splitlines() if not x.startswith('import '))
with tempfile.TemporaryDirectory(prefix='regram-chat-list-') as directory:
    path = Path(directory); swift = path/'Checks.swift'
    swift.write_text(adapters+'\n'+extras+'\n'+bridge['bridge']+'\n'+helper+'\n'+checks)
    sources = list((root/'Regram/RGAdFilter/Sources').glob('*.swift')) + list((root/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',*map(str,sources),str(swift),'-o',str(path/'checks')],check=True)
    subprocess.run([str(path/'checks')],check=True,timeout=60)

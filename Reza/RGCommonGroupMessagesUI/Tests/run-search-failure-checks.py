"""Exercise production failure handling against a small in-memory Postbox boundary."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
groups = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Peers/GroupsInCommon.swift').read_text()
search = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/SearchMessages.swift').read_text()
pane = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/Panes/PeerInfoGroupsInCommonPaneNode.swift').read_text()
pane_start = pane.index('    private func loadMoreIfNeeded()')
pane_open = pane.index('{', pane_start)
pane_end, depth = pane_open + 1, 1
while depth:
    depth += (pane[pane_end] == '{') - (pane[pane_end] == '}')
    pane_end += 1
load_more = pane[pane_start:pane_end]
start = groups.index('                guard let strongSelf = self else {', groups.index('(peers, count, nextMaxId, failed) in'))
end = groups.index('\n            }))', start)
callback = groups[start:end]
retry_guard = next(line.strip() for line in groups.splitlines() if 'if case let .ready(canLoadMore) = self.dataState' in line)
start = search.index('            if case let .peer(peerId, _, _, _, _, _, _) = location {', search.index('var merged = mergedResult(updatedState)'))
end = search.index('\n            return (merged, updatedState)', start)
marker = search[start:end]
fixture = r'''
import Foundation
enum DataState { case loading, ready(canLoadMore: Bool) }
struct Peer { let id: Int }
struct RenderedPeer { let peerId: Int; init(peer: Peer) { peerId = peer.id } }
struct CachedGroupsInCommon { let peerIds: [Int]; let count: Int32 }
struct CodableEntry { init?(_ value: CachedGroupsInCommon) {} }
func entryId(peerId: Int) -> Int { peerId }
final class Transaction {
    var writes = 0
    var migration: CachedChannelData?
    func putItemCacheEntry(id: Int, entry: CodableEntry) { writes += 1 }
    func getPeerCachedData(peerId: Int) -> Any? { migration }
    func getPeer(_ id: Int) -> Int? { id }
}
final class Signal { func start() -> Int { 0 } }
final class Postbox {
    let tx = Transaction()
    func transaction(_ body: (Transaction) -> Void) -> Signal { body(tx); return Signal() }
}
final class MetaDisposable { func set(_ value: Int) {} }
final class Host {
    var peers = [RenderedPeer(peer: Peer(id: 1))]
    var count: Int? = 7
    var dataState = DataState.loading
    var loadFailed = false
    var nextMaxId: Int64?
    var hasLoadedFirstPage = false
    let cacheDisposable = MetaDisposable()
    let postbox = Postbox()
    var pushes = 0
    func pushState() { pushes += 1 }
    var retryAllowed: Bool { RETRY return true }; return false }
    func receive(peers: [Peer], count: Int, failed: Bool, maxId: Int64? = nil, nextMaxId: Int64? = nil) {
        let postbox = self.postbox, peerId = 100
        let completion: ([Peer], Int, Int64?, Bool) -> Void = { [weak self] peers, count, nextMaxId, failed in
            CALLBACK
        }
        completion(peers, count, nextMaxId, failed)
    }
}
final class Queue {
    static let main = Queue()
    static func mainQueue() -> Queue { main }
    var pending: [() -> Void] = []
    func async(_ value: @escaping () -> Void) { pending.append(value) }
    func drain() { while !pending.isEmpty { pending.removeFirst()() } }
}
enum Offset { case known(Double), unknown }
struct PaneState { var loadFailed = false; var dataState: DataState }
final class List { var offset = Offset.known(0); func visibleBottomContentOffset() -> Offset { offset } }
final class Context { var requests = 0; var didLoad: (() -> Void)?; func loadMore() { requests += 1; didLoad?() } }
final class PaneHost {
    var state: PaneState? = PaneState(dataState: .loading)
    var currentEntries = [1]
    let listNode = List(), groupsInCommonContext = Context()
    init() { groupsInCommonContext.didLoad = { [weak self] in self?.state?.dataState = .loading } }
    func request() { loadMoreIfNeeded() }
    LOAD_MORE
}
struct PeerState { let completed: Bool }
struct SearchState { let main: PeerState; let additional: PeerState? }
struct MessageId { let peerId: Int }
struct Migration { let maxMessageId: MessageId }
final class CachedChannelData { let migrationReference: Migration?; init(_ migration: Migration?) { migrationReference = migration } }
func apiInputPeer(_ value: Int) -> Int? { value > 0 ? value : nil }
enum Location { case peer(Int, Int?, Int?, Int?, Int?, Int?, Int?); case other }
struct Result { var rgRequestFailed = false }
func failed(state: SearchState?, main: Int?, additional: Int?, migrated: Bool) -> Bool {
    let transaction = Transaction()
    if migrated { transaction.migration = CachedChannelData(Migration(maxMessageId: MessageId(peerId: 10))) }
    let location = Location.peer(100, 42, nil, nil, nil, nil, nil)
    let result = main, additionalResult = additional
    var merged = Result()
    MARKER
    return merged.rgRequestFailed
}
func expect(_ value: @autoclosure () -> Bool, _ description: String) { if !value() { fatalError(description) } }
@main enum Tests { static func main() {
    let host = Host()
    host.receive(peers: [], count: 0, failed: true)
    expect(host.loadFailed && host.retryAllowed && host.peers.map(\.peerId) == [1] && host.count == 7 && host.postbox.tx.writes == 0, "A failure must preserve cached groups and count, allow retry, and never write an empty cache")
    host.loadFailed = false; host.dataState = .loading
    host.receive(peers: [Peer(id: 1), Peer(id: 2)], count: 7, failed: false, nextMaxId: 2)
    expect(host.peers.map(\.peerId) == [1, 2] && host.count == 7 && host.postbox.tx.writes == 1 && host.retryAllowed, "Successful pages deduplicate and update the cache")
    host.receive(peers: [], count: 0, failed: false, maxId: 2)
    expect(!host.retryAllowed && host.postbox.tx.writes == 1 && host.peers.count == 2, "An exhausted tail must not reload or replace the first-page cache")
    let paging = Host()
    paging.peers = [RenderedPeer(peer: Peer(id: 99))]
    paging.receive(peers: (1...17).map(Peer.init), count: 20, failed: false, nextMaxId: 17)
    expect(paging.peers.count == 17 && !paging.peers.contains(where: { $0.peerId == 99 }) && paging.retryAllowed && paging.nextMaxId == 17, "A stale cached preview is replaced, and 17/20 groups must permit the next page")
    paging.dataState = .loading
    paging.receive(peers: (17...20).map(Peer.init), count: 20, failed: false, maxId: 17, nextMaxId: 20)
    expect(paging.peers.count == 20 && paging.count == 20 && !paging.retryAllowed, "The last three groups load with duplicate boundary rows removed")
    let unrenderable = Host()
    unrenderable.receive(peers: [], count: 20, failed: false, nextMaxId: 40)
    expect(unrenderable.retryAllowed && unrenderable.nextMaxId == 40, "Raw chat cursors advance even when a page has no renderable peers")
    unrenderable.dataState = .loading
    unrenderable.receive(peers: [], count: 20, failed: false, maxId: 40, nextMaxId: 40)
    expect(!unrenderable.retryAllowed && unrenderable.count == 0, "A repeated cursor cannot create an endless pagination loop or retain an unavailable total")
    let retry = Host()
    retry.nextMaxId = 50
    retry.receive(peers: [], count: 0, failed: true, maxId: 50)
    expect(retry.nextMaxId == 50 && retry.peers.count == 1 && retry.count == 7 && retry.retryAllowed, "A failed tail retries the same server cursor without deleting visible groups")
    let complete = Host()
    complete.receive(peers: [Peer(id: 4), Peer(id: 5)], count: 0, failed: false, nextMaxId: 5)
    expect(complete.count == 2 && !complete.retryAllowed && complete.hasLoadedFirstPage, "Unsliced success has the actual loaded count, including an empty first page")
    let pane = PaneHost()
    pane.request()
    pane.state = PaneState(dataState: .ready(canLoadMore: true))
    Queue.main.drain()
    expect(pane.groupsInCommonContext.requests == 1, "An offset reported while loading must be checked again after readiness")
    pane.state = PaneState(dataState: .ready(canLoadMore: true)); pane.listNode.offset = .known(300)
    pane.request(); Queue.main.drain()
    expect(pane.groupsInCommonContext.requests == 1, "Do not eagerly drain distant pages")
    pane.currentEntries = []; pane.listNode.offset = .unknown
    pane.request(); Queue.main.drain()
    expect(pane.groupsInCommonContext.requests == 2, "An unrenderable page must not strand pagination on an unknown offset")
    pane.state = PaneState(loadFailed: true, dataState: .ready(canLoadMore: false))
    pane.request(); Queue.main.drain()
    expect(pane.groupsInCommonContext.requests == 2, "Failures wait for the explicit retry action")
    pane.state = PaneState(dataState: .ready(canLoadMore: false))
    pane.request(); Queue.main.drain()
    expect(pane.groupsInCommonContext.requests == 2, "Exhausted data cannot restart automatic pagination")
    expect(failed(state: nil, main: nil, additional: nil, migrated: false), "First-page network failure is not empty history")
    expect(!failed(state: nil, main: 1, additional: nil, migrated: false), "A valid empty response is successful")
    expect(failed(state: nil, main: 1, additional: nil, migrated: true), "Failure of old-group history must be retriable")
    let partial = SearchState(main: .init(completed: false), additional: .init(completed: false))
    expect(!failed(state: partial, main: 1, additional: nil, migrated: true), "Do not mark deliberately deferred old-group requests as failures")
    let mainDone = SearchState(main: .init(completed: true), additional: .init(completed: false))
    expect(failed(state: mainDone, main: nil, additional: nil, migrated: true), "Detect failed old-group pagination after the main group completes")
    let allDone = SearchState(main: .init(completed: true), additional: .init(completed: true))
    expect(!failed(state: allDone, main: nil, additional: nil, migrated: true), "Completed searches deliberately skip requests")
    print("Production common-group/search handling passed: 17+3 pagination, stale cache replacement, raw/repeated cursors, actual terminal count, explicit retry and migrated-history failures.")
} }
'''.replace('RETRY', retry_guard).replace('CALLBACK', callback).replace('MARKER', marker).replace('LOAD_MORE', load_more)
with tempfile.TemporaryDirectory(prefix='regram-common-group-failures-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], check=True)
    subprocess.run([str(folder / 'tests')], check=True)

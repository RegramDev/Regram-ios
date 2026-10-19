"""Exercise production failure handling against a small in-memory Postbox boundary."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
groups = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Peers/GroupsInCommon.swift').read_text()
search = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/SearchMessages.swift').read_text()
start = groups.index('                guard let strongSelf = self else {', groups.index('(peers, count, failed) in'))
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
    let cacheDisposable = MetaDisposable()
    let postbox = Postbox()
    var pushes = 0
    func pushState() { pushes += 1 }
    var retryAllowed: Bool { RETRY return true }; return false }
    func receive(peers: [Peer], count: Int, failed: Bool, maxId: Int? = nil) {
        let postbox = self.postbox, peerId = 100
        let completion: ([Peer], Int, Bool) -> Void = { [weak self] peers, count, failed in
            CALLBACK
        }
        completion(peers, count, failed)
    }
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
    host.receive(peers: [Peer(id: 1), Peer(id: 2)], count: 7, failed: false)
    expect(host.peers.map(\.peerId) == [1, 2] && host.count == 7 && host.postbox.tx.writes == 1 && host.retryAllowed, "Successful pages deduplicate and update the cache")
    host.receive(peers: [], count: 0, failed: false, maxId: 2)
    expect(!host.retryAllowed && host.postbox.tx.writes == 1 && host.peers.count == 2, "An exhausted tail must not reload or replace the first-page cache")
    expect(failed(state: nil, main: nil, additional: nil, migrated: false), "First-page network failure is not empty history")
    expect(!failed(state: nil, main: 1, additional: nil, migrated: false), "A valid empty response is successful")
    expect(failed(state: nil, main: 1, additional: nil, migrated: true), "Failure of old-group history must be retriable")
    let partial = SearchState(main: .init(completed: false), additional: .init(completed: false))
    expect(!failed(state: partial, main: 1, additional: nil, migrated: true), "Do not mark deliberately deferred old-group requests as failures")
    let mainDone = SearchState(main: .init(completed: true), additional: .init(completed: false))
    expect(failed(state: mainDone, main: nil, additional: nil, migrated: true), "Detect failed old-group pagination after the main group completes")
    let allDone = SearchState(main: .init(completed: true), additional: .init(completed: true))
    expect(!failed(state: allDone, main: nil, additional: nil, migrated: true), "Completed searches deliberately skip requests")
    print("Production common-group/search failure handling passed: cache preservation, explicit retry, empty success and migrated-history failures.")
} }
'''.replace('RETRY', retry_guard).replace('CALLBACK', callback).replace('MARKER', marker)
with tempfile.TemporaryDirectory(prefix='regram-common-group-failures-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], check=True)
    subprocess.run([str(folder / 'tests')], check=True)

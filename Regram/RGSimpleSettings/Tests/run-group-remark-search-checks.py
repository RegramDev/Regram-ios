from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Contacts/TelegramEngineContacts.swift').read_text()
start = source.index('        public func searchLocalPeers(')
end = source.index('        public func searchContacts(', start)
method = source[start:end].replace('public func', 'func').replace('RGGroupRemarks.shared', 'testStore')

# Keep the production search method; adapt only the external database and signal types.
adapters = '''
import Foundation
enum NoError: Error {}
struct Signal<T, E> { let value: T }
infix operator |> : AdditionPrecedence
func |> <A,B>(value: A, f: (A)->B)->B { f(value) }
func map<A,B,E>(_ f: @escaping (A)->B)->(Signal<A,E>)->Signal<B,E> { { Signal(value: f($0.value)) } }
struct PeerId: Hashable { let value: Int64; func toInt64()->Int64 { value } }
protocol Peer { var id: PeerId { get } }
class TelegramGroup: Peer { let id: PeerId; let migrationReference: Int?; init(_ id:Int64, migrated:Bool=false) { self.id=PeerId(value:id); migrationReference=migrated ? 1:nil } }
enum ChannelInfo { case group,broadcast }
class TelegramChannel: Peer { let id: PeerId; let info:ChannelInfo; init(_ id:Int64,_ info:ChannelInfo) {self.id=PeerId(value:id); self.info=info} }
class TelegramUser: Peer { let id:PeerId; let botInfo:Bool?=nil; init(_ id:Int64) {self.id=PeerId(value:id)} }
struct RenderedPeer {let peer:Peer?; var peerId:PeerId {peer!.id}; init(peer:Peer) {self.peer=peer} }
struct EngineRenderedPeer {let peerId:PeerId; init(_ peer:RenderedPeer) {peerId=peer.peerId} }
enum TelegramSearchPeersScope {case everywhere,channels,groups,privateChats,bots,globalPosts}
enum Namespaces {enum PeerGroup {static let archive=PeerGroupId(rawValue:1)}}
struct ChatListFilterPredicate {let ids:Set<Int64>}
final class Transaction {
 var root:[Peer]=[],archive:[Peer]=[],normal:[Peer]=[]
 func searchPeers(query:String,predicate:ChatListFilterPredicate?)->[RenderedPeer] {
  normal.filter {predicate?.ids.contains($0.id.value) ?? true}.map {RenderedPeer(peer:$0)}
 }
 func getChatListPeers(groupId:PeerGroupId,filterPredicate:ChatListFilterPredicate?,additionalFilter:((Peer)->Bool)?)->[Peer] {
  (groupId == .root ? root:archive).filter {
   (filterPredicate?.ids.contains($0.id.value) ?? true) && (additionalFilter?($0) ?? true)
  }
 }
}
final class Postbox {
 let t=Transaction()
 func searchPeers(query:String,predicate:ChatListFilterPredicate?)->Signal<[RenderedPeer],NoError> {Signal(value:t.searchPeers(query:query,predicate:predicate))}
 func transaction<T>(_ f:(Transaction)->T)->Signal<T,NoError> {Signal(value:f(t))}
}
final class Account {let peerId:PeerId;let postbox:Postbox;init(_ id:Int64,_ postbox:Postbox) {peerId=PeerId(value:id);self.postbox=postbox}}
let suite="Regram.GroupRemarks.SearchTests."+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
let testStore=RGGroupRemarks(defaults:defaults,notifications:NotificationCenter())
final class Contacts {let account:Account;init(_ account:Account) {self.account=account}
'''
tests = '''
}
@main enum Tests {
 static func main() {
  defer {defaults.removePersistentDomain(forName:suite)}
  let p=Postbox();let regular=TelegramGroup(11),archived=TelegramChannel(12,.group)
  p.t.root=[regular,TelegramChannel(13,.broadcast),TelegramUser(14),TelegramGroup(15,migrated:true)]
  p.t.archive=[archived];p.t.normal=[regular]
  for id in 11...16 {testStore.setName("Local Name",accountId:1,peerId:Int64(id))}
  let c=Contacts(Account(1,p))
  func ids(_ scope:TelegramSearchPeersScope = .everywhere,_ predicate:ChatListFilterPredicate?=nil)->[Int64] {
   c.searchLocalPeers(query:"local name",scope:scope,predicate:predicate).value.map {$0.peerId.value}
  }
  precondition(ids()==[11,13,12],"Deduplicate original-name hits and include channel aliases while excluding users, migrated or removed groups")
  precondition(ids(.groups)==[11,12])
  precondition(ids(.channels)==[13],"Channel scope must include only broadcast aliases")
  precondition(ids(.privateChats).isEmpty && ids(.bots).isEmpty)
  precondition(ids(.everywhere,ChatListFilterPredicate(ids:[12]))==[12],"A remark must not bypass the current folder filter")
  let other=Contacts(Account(2,p));p.t.normal=[]
  precondition(other.searchLocalPeers(query:"local name").value.isEmpty,"Do not expose another account's remarks")
  testStore.setName("",accountId:1,peerId:12)
  precondition(ids()==[11,13],"Clearing a group name retains the channel alias")
  testStore.setName("",accountId:1,peerId:13)
  precondition(ids()==[11],"Clearing a channel name removes its alias match")
  print("Production group search checks passed with database adapters: scope, folder predicate, archive, deduplication, removed/migrated peers and account isolation.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-group-search-') as directory:
    path = Path(directory)
    (path / 'Tests.swift').write_text(adapters + method + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                    str(root / 'submodules/Postbox/Sources/PeerGroup.swift'),
                    str(root / 'Regram/RGSimpleSettings/Sources/GroupRemarks.swift'),
                    str(path / 'Tests.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)

#!/usr/bin/env python3
"""Exercise production placement persistence with isolated Postbox transaction adapters."""
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[3]
source=(ROOT/'Regram/RGChatListPlacement/Sources/RGChatListPlacement.swift').read_text().replace('import Postbox\n','')
fixture=r'''
import Foundation
struct PeerId: Hashable { let value: Int64; init(_ value: Int64) { self.value=value }; func toInt64()->Int64 { value } }
struct PeerGroupId: Equatable { let rawValue: Int32; init(rawValue: Int32) { self.rawValue=rawValue }; static let root=PeerGroupId(rawValue:0); static let archive=PeerGroupId(rawValue:1) }
struct ValueBoxKey: Hashable { let rawValue: String; init(_ value: String) { rawValue=value } }
struct PreferencesEntry { let data: Data; init<T: Encodable>(_ value:T) { data=try! JSONEncoder().encode(value) }; func get<T:Decodable>(_ type:T.Type)->T? { try? JSONDecoder().decode(type,from:data) } }
struct Inclusion { let groupId: PeerGroupId? }
final class Transaction {
 var preferences:[ValueBoxKey:PreferencesEntry]=[:]; var groups:[PeerId:PeerGroupId]=[:]
 func getPreferencesEntry(key:ValueBoxKey)->PreferencesEntry? { preferences[key] }
 func updatePreferencesEntry(key:ValueBoxKey,_ f:(PreferencesEntry?)->PreferencesEntry?) { preferences[key]=f(preferences[key]) }
 func getPeerChatListInclusion(_ id:PeerId)->Inclusion { Inclusion(groupId:groups[id]) }
}
'''
tests=r'''
@main struct Tests {
 static func main() {
  let a=Transaction(), b=Transaction(), peer=PeerId(12), other=PeerId(13)
  func check(_ value:Bool,_ message:String) { precondition(value,message) }
  check(rgRestoredChatListGroup(transaction:a,peerId:peer)==(.root),"unknown defaults to root")
  a.groups[peer] = .archive
  rgRememberChatListPlacement(transaction:a,peerId:peer)
  a.groups[peer] = nil
  check(rgRestoredChatListGroup(transaction:a,peerId:peer)==(.archive),"temporary community hiding retains archive")
  let reopened=Transaction(); reopened.preferences=a.preferences
  check(rgRestoredChatListGroup(transaction:reopened,peerId:peer)==(.archive),"serialized state survives restart")
  check(rgRestoredChatListGroup(transaction:b,peerId:peer)==(.root),"account isolation")
  let revision=rgChatListPlacementRevision(transaction:a)
  rgRememberChatListPlacement(transaction:a,peerId:peer,group:.root,interactive:true)
  check(rgRestoredChatListGroup(transaction:a,peerId:peer)==(.root),"explicit unarchive replaces retained archive")
  check(rgChatListPlacementChanged(transaction:a,peerId:peer,after:revision),"stale pinned fetch detects local move")
  check(!rgChatListPlacementChanged(transaction:a,peerId:other,after:revision),"unrelated peer does not suppress server pins")
  check(!rgChatListPlacementChanged(transaction:a,peerId:peer,after:rgChatListPlacementRevision(transaction:a)),"new fetch accepts current placement")
  a.groups[peer] = .root; rgRememberChatListPlacement(transaction:a,peerId:peer)
  check(rgChatListPlacementChanged(transaction:a,peerId:peer,after:revision),"community updates retain move revision")
  let beforeArchive=rgChatListPlacementRevision(transaction:a)
  rgRememberChatListPlacement(transaction:a,peerId:peer,group:.archive,interactive:true)
  check(rgPendingChatListPlacements(transaction:a).contains(peer),"archive remains pending until acknowledged")
  check(rgResolveChatListGroup(transaction:a,peerId:peer,serverGroup:.root)==(.archive),"old server response cannot override pending archive")
  rgConfirmChatListPlacement(transaction:a,peerId:peer,group:.root)
  check(rgPendingChatListPlacements(transaction:a).contains(peer),"old opposite acknowledgement cannot clear pending move")
  let pendingAtFetch=rgPendingChatListPlacements(transaction:a)
  rgConfirmChatListPlacement(transaction:a,peerId:peer,group:.archive)
  check(!rgPendingChatListPlacements(transaction:a).contains(peer),"matching acknowledgement clears pending move")
  check(pendingAtFetch.contains(peer) && rgChatListPlacementChanged(transaction:a,peerId:peer,after:beforeArchive),"fetch snapshot protects responses that finish after acknowledgement")
  check(rgResolveChatListGroup(transaction:a,peerId:peer,serverGroup:.root)==(.root),"future server updates are accepted after acknowledgement")
  print("Chat placement: 15 checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-placement-') as temp:
 p=Path(temp); (p/'main.swift').write_text(fixture+source+tests)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-warnings-as-errors',str(p/'main.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)

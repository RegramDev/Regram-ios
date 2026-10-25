#!/usr/bin/env python3
"""Exercise placement persistence with the production binary Postbox codecs and isolated transactions."""
from pathlib import Path
import argparse
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--keyed-decoder',type=Path,help='Optional pre-fix decoder for regression verification')
args=parser.parse_args()
source=(ROOT/'Regram/RGChatListPlacement/Sources/RGChatListPlacement.swift').read_text().replace('import Postbox\n','')
fixture=r'''
import Foundation
func postboxLog(_ value: String) {}
func mdb_cmp_memn(_ a: UnsafeRawPointer, _ al: Int, _ b: UnsafeRawPointer, _ bl: Int) -> Int32 { let v = memcmp(a,b,min(al,bl)); return v != 0 ? v : (al == bl ? 0 : (al < bl ? -1 : 1)) }
public struct MediaResourceId {}
struct PeerId: Hashable { let value: Int64; init(_ value: Int64) { self.value=value }; func toInt64()->Int64 { value } }
struct PeerGroupId: Equatable { let rawValue: Int32; init(rawValue: Int32) { self.rawValue=rawValue }; static let root=PeerGroupId(rawValue:0); static let archive=PeerGroupId(rawValue:1) }
struct ValueBoxKey: Hashable { let rawValue: String; init(_ value: String) { rawValue=value } }
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
  var count=0
  func check(_ value:Bool,_ message:String) { precondition(value,message); count += 1 }
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
  // Existing b34636 bytes must reopen without deleting preferences or changing their format.
  let large=PeerId(Int64.min + 7)
  var legacy=RGChatPlacementState()
  legacy.revision=19
  legacy.entries[String(large.toInt64())] = .init(group:1,revision:18,pending:nil)
  legacy.entries["12"] = .init(group:0,revision:19,pending:true)
  let saved=PreferencesEntry(legacy)!
  let migrated=Transaction()
  migrated.preferences[rgPlacementKey]=PreferencesEntry(data:saved.data)
  check(rgRestoredChatListGroup(transaction:migrated,peerId:large)==(.archive),"old binary entries and 64-bit peer keys survive")
  check(rgChatListPlacementRevision(transaction:migrated)==19,"old revision survives")
  check(rgPendingChatListPlacements(transaction:migrated)==[peer],"old pending flag and absent optional flag survive")
  rgRememberChatListPlacement(transaction:migrated,peerId:large,group:.root,interactive:true)
  check(rgChatListPlacementRevision(transaction:migrated)==20,"decoded revision continues on next move")
  let afterMove=Transaction()
  afterMove.preferences[rgPlacementKey]=PreferencesEntry(data:migrated.preferences[rgPlacementKey]!.data)
  check(rgRestoredChatListGroup(transaction:afterMove,peerId:large)==(.root),"updated binary preferences reopen")
  check(rgPendingChatListPlacements(transaction:afterMove)==[peer,large],"pending moves survive another reopen")
  let empty=PreferencesEntry(RGChatPlacementState())!
  check(empty.get(RGChatPlacementState.self)?.entries.isEmpty == true,"empty dictionary decodes")
  let nested=["中文":["-123":RGChatPlacementState.Entry(group:1,revision:7,pending:true)]]
  let nestedResult=CodableEntry(nested)!.get([String:[String:RGChatPlacementState.Entry]].self)
  check(nestedResult?["中文"]?["-123"]?.revision==7,"nested dictionaries and UTF-8 keys decode")
  let integers=[-42:RGChatPlacementState.Entry(group:1,revision:8,pending:false)]
  check(CodableEntry(integers)!.get([Int:RGChatPlacementState.Entry].self)?[-42]?.group==1,"integer dictionary keys decode")
  let encoder=PostboxEncoder()
  encoder.encodeInt32(1,forKey:"i"); encoder.encodeInt64(2,forKey:"l")
  encoder.encodeBool(true,forKey:"b"); encoder.encodeDouble(1.5,forKey:"d")
  encoder.encodeString("value",forKey:"s"); encoder.encodeNil(forKey:"n")
  encoder.encodeData(Data([1,2]),forKey:"bytes")
  encoder.encode([Int32(1),Int32(2)],forKey:"ia")
  encoder.encode([Int64(3)],forKey:"la")
  encoder.encode(["a","b"],forKey:"sa")
  encoder.encode([Data([3])],forKey:"ba")
  encoder.encode([legacy],forKey:"oa")
  encoder.encode(legacy,forKey:"o")
  let decoder=PostboxDecoder(buffer:MemoryBuffer(data:encoder.makeData()))
  let expected:Set<String>=["i","l","b","d","s","n","bytes","ia","la","sa","ba","oa","o"]
  check(Set(decoder.decodeKeyNames())==expected,"enumeration skips all encoded value shapes")
  check(decoder.decodeOptionalInt32ForKey("i")==1,"enumeration preserves decoder position")
  check(Set(decoder.decodeKeyNames())==expected,"repeated enumeration is independent of reads")
  check(decoder.decodeOptionalStringForKey("s")=="value","later value reads still work")
  for malformed in [Data([255]),Data([2,65]),Data([1,65,255]),Data([1,65,4,255,255,255,127])] {
   check(PostboxDecoder(buffer:MemoryBuffer(data:malformed)).decodeKeyNames().isEmpty,"malformed key/value scan is bounded")
  }
  print("Chat placement and binary Postbox dictionaries: \(count) checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-placement-') as temp:
 p=Path(temp); (p/'main.swift').write_text(fixture+source+tests)
 header=ROOT/'submodules/MurMurHash32/PublicHeaders/MurMurHash32/MurMurHash32.h'
 (p/'module.modulemap').write_text('module MurMurHash32 { header "'+str(header)+'" export * }\n')
 subprocess.run(['xcrun','clang','-dynamiclib','-fobjc-arc','-framework','Foundation','-I',str(ROOT/'submodules/MurMurHash32/PublicHeaders'),str(ROOT/'submodules/MurMurHash32/Sources/MurMurHash32.m'),'-o',str(p/'libMurMurHash32.dylib')],check=True)
 codecs=sorted((ROOT/'submodules/Postbox/Sources/Utils').rglob('*.swift'))
 if args.keyed_decoder:
  codecs=[args.keyed_decoder.resolve() if x.name=='AdaptedPostboxKeyedDecodingContainer.swift' else x for x in codecs]
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-warnings-as-errors','-I',str(p),'-L',str(p),'-lMurMurHash32','-Xlinker','-rpath','-Xlinker',str(p),str(ROOT/'submodules/Postbox/Sources/Coding.swift'),str(ROOT/'submodules/Postbox/Sources/PreferencesEntry.swift'),*map(str,codecs),str(p/'main.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)

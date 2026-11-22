#!/usr/bin/env python3
"""Exercise production folder persistence and remote merges without an account."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
path = 'submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift'
source = subprocess.check_output(['git', 'show', '85edf2a613:'+path], cwd=ROOT, text=True) if args.baseline else (ROOT/path).read_text()
start = source.index('struct ChatListFiltersState:')
end = source.index('\nfunc _internal_generateNewChatListFilterId', start)
production = source[start:end]
merge_start = source.index('                        let currentFilters = state.filters', source.index('private func synchronizeChatListFilters'))
merge_end = source.index('                        return state', merge_start)
production += '\nfunc applyRemote(_ state: inout ChatListFiltersState, _ remoteFilters: [ChatListFilter], _ remoteTagsEnabled: Bool) {\n'+source[merge_start:merge_end]+' state.normalize()\n}\n'
if args.baseline:
    production += '\nextension ChatListFiltersState { mutating func recordLocalTagColors(in filters: [ChatListFilter]) {} }\n'
fixture = r'''
import Foundation
typealias PeerId = Int64
extension PeerNameColor: Codable {
 public init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(Int32.self)) }
 public func encode(to encoder: Encoder) throws { var values=encoder.singleValueContainer(); try values.encode(self.rawValue) }
}
struct FilterData: Codable, Equatable { var color: PeerNameColor? }
enum ChatListFilter: Codable, Equatable {
 case allChats
 case filter(id: Int32, title: String, emoticon: String?, data: FilterData)
 var id: Int32 { if case let .filter(id,_,_,_) = self { return id }; return 0 }
 var data: FilterData? { if case let .filter(_,_,_,data) = self { return data }; return nil }
 func withLocalOnlyPeers(from filter: ChatListFilter?) -> ChatListFilter { self }
}
struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
 let stringValue: String; var intValue: Int? { Int(stringValue) }
 init(stringLiteral value: String) { stringValue=value }
 init?(stringValue: String) { self.stringValue=stringValue }
 init?(intValue: Int) { stringValue=String(intValue) }
}
func folder(_ id: Int32, _ color: PeerNameColor?, title: String="folder") -> ChatListFilter { .filter(id:id,title:title,emoticon:nil,data:FilterData(color:color)) }
'''
tests = r'''
@main struct Tests {
 static func main() throws {
  var count=0
  func check(_ value: Bool, _ text: String) { count += 1; precondition(value,text) }
  func reopen(_ state: ChatListFiltersState) throws -> ChatListFiltersState { try JSONDecoder().decode(ChatListFiltersState.self,from:JSONEncoder().encode(state)) }
  func edit(_ state: inout ChatListFiltersState, _ filters: [ChatListFilter]) {
   state.recordLocalTagColors(in: filters); state.filters=filters; state.normalize()
  }
  var state=ChatListFiltersState.default
  check(state.localDisplayTags==nil && !state.displayTags,"new account default")
  state.displayTags=true; state.localDisplayTags=true
  edit(&state,[.allChats,folder(2,.red),folder(3,.green)])
  state=try reopen(state)
  check(state.filters[1].data?.color == .red,"custom color survives coding")
  applyRemote(&state,[.allChats,folder(2,nil),folder(3,nil)],false)
  check(state.filters[1].data?.color == .red,"remote missing color cannot erase chosen red")
  check(state.filters[2].data?.color == .green,"colors are stored per folder")
  check(state.displayTags,"remote non-Premium false cannot disable local tags")
  state=try reopen(state)
  applyRemote(&state,[.allChats,folder(3,.blue),folder(2,.blue,title:"renamed"),folder(4,.pink)],false)
  check(state.filters.map(\.id) == [0,3,2,4],"remote reordering and added folders are retained")
  check(state.filters[1].data?.color == .green && state.filters[2].data?.color == .red,"server defaults cannot replace local colors")
  check(state.filters[2] == folder(2,.red,title:"renamed"),"remote title changes still apply")
  check(state.filters[3].data?.color == .pink,"untouched remote folder colors still apply")
  edit(&state,[.allChats,folder(3,.green),folder(2,nil),folder(4,.pink)])
  state=try reopen(state)
  applyRemote(&state,[.allChats,folder(3,nil),folder(2,.red),folder(4,.pink)],true)
  check(state.filters[2].data?.color == nil,"explicit no-tag survives restart and server color")
  state.localDisplayTags=false; state.displayTags=false
  state=try reopen(state); applyRemote(&state,state.filters,true)
  check(!state.displayTags,"explicit off survives remote true")
  check(state.filters[1].data?.color == .green,"hiding tags does not lose color")
  // The update helper also normalizes live push updates from StateReplay.
  state.filters=[.allChats,folder(3,.blue),folder(2,.blue),folder(4,.pink)]; state.normalize()
  check(state.filters[1].data?.color == .green && state.filters[2].data?.color == nil,"live server pushes preserve local choices")
  edit(&state,[.allChats,folder(4,.pink)])
  applyRemote(&state,[.allChats,folder(3,.cyan),folder(4,.pink)],true)
  check(state.filters[1].data?.color == .cyan,"deleted folder id can be reused without stale color")
  let encoder=JSONEncoder(), decoder=JSONDecoder()
  var legacyObject:[String:Any]=["filters":try JSONSerialization.jsonObject(with:encoder.encode([folder(2,.orange)])),"displayTags":true]
  var legacy=try decoder.decode(ChatListFiltersState.self,from:JSONSerialization.data(withJSONObject:legacyObject))
  applyRemote(&legacy,[folder(2,nil)],false)
  check(legacy.filters[0].data?.color == .orange,"existing pre-fix colored folders migrate on first load")
  legacyObject["filters"]=try JSONSerialization.jsonObject(with:encoder.encode([folder(2,nil)]))
  legacy=try decoder.decode(ChatListFiltersState.self,from:JSONSerialization.data(withJSONObject:legacyObject))
  applyRemote(&legacy,[folder(2,.violet)],true)
  check(legacy.filters[0].data?.color == .violet,"old unset folders retain server colors")
  var other=ChatListFiltersState.default
  applyRemote(&other,[folder(2,.blue)],false)
  check(other.filters[0].data?.color == .blue && other.localDisplayTags==nil,"same folder id is isolated by account state")
  print("Folder tags: \(count) persistence and sync checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-tags-') as temp:
    p=Path(temp)
    colors=(ROOT/'submodules/TelegramCore/Sources/SyncCore/SyncCore_CachedUserData.swift').read_text()
    color_start=colors.index('public enum PeerNameColor:')
    colors=colors[color_start:colors.index('    public init(flatBuffersObject:',color_start)]+'}\n'
    (p/'main.swift').write_text('import Foundation\n'+colors+fixture+production+tests)
    subprocess.run(['xcrun','swiftc','-parse-as-library','-warnings-as-errors',str(p/'main.swift'),'-o',str(p/'tests')],check=True)
    subprocess.run([str(p/'tests')],check=True)

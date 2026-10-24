#!/usr/bin/env python3
"""Round-trip the production account folder state, including local tag display choices."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[3]
source=(ROOT/'submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift').read_text()
start=source.index('struct ChatListFiltersState:'); end=source.index('\nfunc _internal_generateNewChatListFilterId',start)
production=source[start:end]
merge_start=source.index('                        state.displayTags = state.localDisplayTags ?? remoteTagsEnabled')
merge_end=source.index('                        return state',merge_start)
production += '\nfunc applyRemote(_ state: inout ChatListFiltersState, _ remoteTagsEnabled: Bool) {\n'+source[merge_start:merge_end]+'}\n'
fixture=r'''
import Foundation
typealias PeerId=Int64
struct ChatListFilter:Codable,Equatable { let id:Int32 }
struct StringCodingKey:CodingKey,ExpressibleByStringLiteral {
 let stringValue:String; var intValue:Int? { Int(stringValue) }; init(stringLiteral value:String) { stringValue=value }; init?(stringValue:String) { self.stringValue=stringValue }; init?(intValue:Int) { stringValue=String(intValue) }
}
'''
tests=r'''
@main struct Tests {
 static func main() throws {
  func check(_ value:Bool,_ text:String) { precondition(value,text) }
  let encoder=JSONEncoder(), decoder=JSONDecoder()
  var state=ChatListFiltersState.default
  check(state.localDisplayTags==nil && !state.displayTags,"new account default")
  state.displayTags=true; state.localDisplayTags=true
  var reopened=try decoder.decode(ChatListFiltersState.self,from:encoder.encode(state))
  check(reopened.localDisplayTags==true && reopened.displayTags,"enabled survives restart")
  // This is the production remote-sync assignment.
  applyRemote(&reopened, false)
  check(reopened.displayTags,"remote non-Premium false does not disable local tags")
  reopened=try decoder.decode(ChatListFiltersState.self,from:encoder.encode(reopened))
  check(reopened.displayTags,"second restart keeps override")
  reopened.localDisplayTags=false; reopened.displayTags=false
  reopened=try decoder.decode(ChatListFiltersState.self,from:encoder.encode(reopened))
  applyRemote(&reopened, true)
  check(!reopened.displayTags,"explicit off survives remote true")
  let legacy=try decoder.decode(ChatListFiltersState.self,from:Data(#"{"filters":[],"displayTags":true}"#.utf8))
  check(legacy.displayTags,"legacy enabled state remains readable")
  let independent=ChatListFiltersState.default
  check(independent.localDisplayTags==nil,"other account remains independent")
  print("Folder tags: 7 checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-tags-') as temp:
 p=Path(temp); (p/'main.swift').write_text(fixture+production+tests)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-warnings-as-errors',str(p/'main.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)

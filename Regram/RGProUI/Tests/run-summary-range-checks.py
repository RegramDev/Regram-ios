"""Exercise the production range loader using real SwiftSignalKit and synthetic search pages."""
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-summary-range-') as directory:
 work=Path(directory)
 sources=sorted((root/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
 subprocess.run(['xcrun','swiftc','-swift-version','5','-emit-library','-emit-module','-module-name','SwiftSignalKit']+[str(p) for p in sources]+['-emit-module-path',str(work/'SwiftSignalKit.swiftmodule'),'-o',str(work/'libSwiftSignalKit.dylib')],check=True,capture_output=True)
 source=(root/'Regram/RGProUI/Sources/RGMessageSummaryRangeController.swift').read_text()
 a=source.index('private final class RGSummaryRangeLoader');b=source.index('\nprivate struct RGSummaryRangeView',a)
 adapter='''import Foundation
import Combine
import SwiftSignalKit
typealias PeerId=Int64
typealias MessageId=Int
struct Message { let id:Int; let timestamp:Int32; let text:String; var containsSecretMedia=false; var protected=false; var index:Int {id}; var rgTextContent:String{text}; func isCopyProtected()->Bool{protected} }
struct SearchMessagesState:Equatable {let cursor:Int}
struct SearchMessagesResult {let messages:[Message];let completed:Bool;var rgRequestFailed=false}
enum SearchMessagesLocation {case peer(peerId:PeerId,fromId:PeerId?,tags:Int?,reactions:Int?,threadId:Int64?,minDate:Int32?,maxDate:Int32?)}
final class API {
 var output:[(SearchMessagesResult,SearchMessagesState)]=[];var calls=0;var cancelled=0
 var pending:SwiftSignalKit.Subscriber<(SearchMessagesResult,SearchMessagesState),NoError>?
 func searchMessages(location:SearchMessagesLocation,query:String,state:SearchMessagesState?,limit:Int)->Signal<(SearchMessagesResult,SearchMessagesState),NoError>{
  precondition(query.isEmpty && limit==100)
  if case let .peer(peer,_,_,_,thread,lower,upper)=location {precondition(peer==99 && thread==42 && lower==100 && upper==200)}
  calls+=1
  if !output.isEmpty {return .single(output.removeFirst())}
  return Signal{subscriber in self.pending=subscriber;return ActionDisposable{self.cancelled+=1}}
 }
}
final class Engine {let messages=API()}
final class AccountContext {let engine=Engine()}
final class RGSimpleSettings {static let shared=RGSimpleSettings();var messageSummaryEnabled=true}
'''
 tests='''
@main enum Tests {
 static func wait(_ predicate:()->Bool) {let deadline=Date().addingTimeInterval(3);while !predicate() && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(predicate())}
 static func main() {
  let context=AccountContext();var loader:RGSummaryRangeLoader?=RGSummaryRangeLoader(context:context,peerId:99,threadId:42)
  func load(){loader!.load(from:Date(timeIntervalSince1970:100),to:Date(timeIntervalSince1970:200))}
  RGSimpleSettings.shared.messageSummaryEnabled=false;load();precondition(context.engine.messages.calls==0 && loader!.errorKey != nil);RGSimpleSettings.shared.messageSummaryEnabled=true
  let one=Message(id:1,timestamp:100,text:"first"),two=Message(id:2,timestamp:200,text:"last")
  context.engine.messages.output=[(.init(messages:[two,one,Message(id:3,timestamp:150,text:"",protected:false),Message(id:4,timestamp:201,text:"outside"),Message(id:5,timestamp:120,text:"secret",containsSecretMedia:true)],completed:false),.init(cursor:1)),(.init(messages:[two,one,Message(id:6,timestamp:150,text:"protected",protected:true)],completed:true),.init(cursor:2))]
  load();wait{!loader!.loading};precondition(loader!.messages.map(\\.id)==[1,2] && loader!.errorKey==nil && context.engine.messages.calls==2)
  context.engine.messages.output=[(.init(messages:[Message(id:7,timestamp:110,text:String(repeating:"中",count:22000))],completed:true),.init(cursor:1))]
  load();wait{!loader!.loading};precondition(loader!.messages.isEmpty && loader!.errorKey=="Summary.RangeTooLarge")
  for messages in [[],[one]] {
   context.engine.messages.output=[(.init(messages:messages,completed:true,rgRequestFailed:true),.init(cursor:1))]
   load();wait{!loader!.loading};precondition(loader!.messages.isEmpty && loader!.errorKey=="Summary.RangeFailed", "Failed or partial RPC data must never become a summary")
  }
  context.engine.messages.output=[(.init(messages:[one],completed:false),.init(cursor:1)),(.init(messages:[],completed:true,rgRequestFailed:true),.init(cursor:2))]
  load();wait{!loader!.loading};precondition(loader!.messages.isEmpty && loader!.errorKey=="Summary.RangeFailed", "Later-page failures must not publish accumulated partial text")
  context.engine.messages.output=[(.init(messages:[],completed:false),.init(cursor:8)),(.init(messages:[],completed:false),.init(cursor:8))]
  load();wait{!loader!.loading};precondition(loader!.errorKey=="Summary.RangeFailed")
  load();wait{context.engine.messages.pending != nil};loader!.cancel();context.engine.messages.pending?.putNext((.init(messages:[one],completed:true),.init(cursor:1)));precondition(loader!.messages.isEmpty && !loader!.loading && context.engine.messages.cancelled>0)
  weak var weakLoader=loader;loader=nil;wait{weakLoader==nil}
  print("Production summary range checks passed: opt-in, chat/topic date bounds, paginated deduplication, protected/ephemeral exclusion, UTF-8 budget, stalled paging, cancellation and release.")
 }
}
'''.replace('\\\\.id','\\.id')
 (work/'Checks.swift').write_text(adapter+source[a:b]+tests)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-I',str(work),'-L',str(work),'-lSwiftSignalKit','-Xlinker','-rpath','-Xlinker',str(work),str(work/'Checks.swift'),'-o',str(work/'checks')],check=True)
 subprocess.run([str(work/'checks')],check=True,timeout=30)

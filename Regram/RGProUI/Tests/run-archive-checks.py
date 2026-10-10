from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-archive-checks-') as directory:
 work=Path(directory)
 source=(root/'Regram/RGProUI/Sources/RGRevokedMessagesController.swift').read_text().split('private struct RGRevokedMessagesView')[0]
 source='\n'.join(line for line in source.splitlines() if not line.startswith('import '))
 harness='''
import Foundation
import Combine
struct EnginePeer { let id: Int64 }
struct MessageIndex: Comparable { let value: Int; static func <(a:Self,b:Self)->Bool { a.value<b.value }; static func upperBound(peerId:Int64,namespace:Int32)->Self { .init(value:Int.max) }; static func lowerBound(peerId:Int64,namespace:Int32)->Self { .init(value:Int.min) } }
class RGRevokedMessageAttribute {}
struct Message { let id:Int; let namespace:Int32; let index:MessageIndex; var attributes:[Any] }
enum Namespaces { enum Message { static let Cloud:Int32=0,Local:Int32=1,SecretIncoming:Int32=2 } }
protocol Disposable { func dispose() }
class EmptyDisposable:Disposable { func dispose() {} }
class MetaDisposable { func set(_ value:Disposable?){};func dispose(){} }
enum NoError:Error {}
struct Signal<T,E:Error> { let value:T;func start(next:@escaping(T)->Void)->Disposable { Scheduler.pending.append {next(value)}; return EmptyDisposable() } }
infix operator |> : AdditionPrecedence
func |> <A,B>(value:A,transform:(A)->B)->B {transform(value)}
func deliverOnMainQueue<T,E>(_ signal:Signal<T,E>) -> Signal<T,E> { signal }
enum Scheduler { static var pending:[()->Void]=[];static func flush(){let old=pending;pending=[];for callback in old{callback()}} }
class Transaction {
 var rows:[Message]=[];var deleted:[Int]=[];var reads=0
 func getMessages(peerId:Int64,namespace:Int32,from:MessageIndex,includeFrom:Bool,to:MessageIndex,limit:Int)->[Message] {reads += 1;return Array(rows.filter{$0.namespace==namespace && $0.index<from}.sorted{$0.index>$1.index}.prefix(limit))}
 func getMessage(_ id:Int)->Message? {rows.first{$0.id==id}}
}
class Postbox {let store=Transaction();func transaction<T>(_ body:(Transaction)->T)->Signal<T,NoError> {.init(value:body(store))} }
class Account {let postbox=Postbox()}
class Messages {func deleteMessages(transaction:Transaction,ids:[Int]) {transaction.deleted += ids;transaction.rows.removeAll{ids.contains($0.id)}}}
class Engine {let messages=Messages()}
class AccountContext {let account=Account();let engine=Engine()}
'''
 tests='''
@main enum Checks {
 static func expect(_ condition:Bool,_ message:String){if !condition{fatalError(message)}}
 static func main(){
  let context=AccountContext()
  context.account.postbox.store.rows=(0..<401).map{Message(id:$0,namespace:0,index:.init(value:$0),attributes:$0 % 5 == 0 ? [RGRevokedMessageAttribute()] : [])}
  let history=RGRevokedHistory(context:context)
  history.select(EnginePeer(id:1));Scheduler.flush()
  expect(history.scanned==150 && history.hasMore && history.messages.count==30,"First page must be bounded and filter retained records")
  history.load();Scheduler.flush();history.load();Scheduler.flush()
  expect(history.scanned==401 && !history.hasMore && history.messages.count==81,"All pages must advance without skips/duplicates and detect the end")
  let stale=context.account.postbox.store.rows.firstIndex{$0.id==400}!
  context.account.postbox.store.rows[stale].attributes=[]
  history.clearLoaded();Scheduler.flush()
  expect(!context.account.postbox.store.deleted.contains(400) && context.account.postbox.store.deleted.count==80,"Cleanup must revalidate markers and preserve a record that is no longer revoked")
  expect(!history.loading && history.messages.isEmpty,"Cleanup must finish without leaving loading stuck")
  history.select(EnginePeer(id:1));let callbacks=Scheduler.pending;Scheduler.pending=[]
  history.select(EnginePeer(id:2));Scheduler.flush();let current=history.scanned
  for callback in callbacks{callback()}
  expect(history.peer?.id==2 && history.scanned==current,"Late page callbacks must not overwrite a newer chat selection")
  print("Archive checks passed: bounded 150-record pages, 401-record cursor progression, deduplication, end detection, marker-checked cleanup and late callback isolation")
 }
}
'''
 p=work/'Checks.swift';p.write_text(harness+source+tests)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5',str(p),'-o',str(work/'checks')],check=True)
 subprocess.run([str(work/'checks')],check=True,timeout=30)

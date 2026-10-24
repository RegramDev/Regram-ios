#!/usr/bin/env python3
"""Run production recurrence lifecycle against isolated transactional and signal adapters."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[3]
source=(ROOT/'Regram/RGRecurringMessages/Sources/RGLocalRecurringMessages.swift').read_text().replace('import Postbox\n','').replace('import SwiftSignalKit\n','')
policy=(ROOT/'Regram/RGRecurringMessages/Sources/RGRecurringSchedulePolicy.swift').read_text()
fixture=r'''
import Foundation
struct PeerId: Hashable,Codable { let value:Int64; init(_ value:Int64) { self.value=value } }
struct MessageId:Hashable,Codable { let peerId:PeerId; let namespace:Int32; let id:Int32 }
enum Namespaces { enum Message { static let ScheduledCloud:Int32=2, ScheduledLocal:Int32=3; static let allScheduled:Set<Int32>=[2,3] } }
struct ValueBoxKey:Hashable { let value:String; init(_ value:String) { self.value=value } }
struct PreferencesEntry { let data:Data; init<T:Encodable>(_ value:T) { data=try! JSONEncoder().encode(value) }; func get<T:Decodable>(_ type:T.Type)->T? { try? JSONDecoder().decode(type,from:data) } }
protocol PostboxCoding {}
protocol MessageAttribute:AnyObject,PostboxCoding {}
struct MediaId:Hashable {}
protocol Media:PostboxCoding {}
final class SampleMedia:Media {}
final class TextAttribute:MessageAttribute {}
final class ScheduledRepeatAttribute:MessageAttribute { let repeatPeriod:Int32; init(repeatPeriod:Int32) { self.repeatPeriod=repeatPeriod } }
final class OutgoingScheduleInfoMessageAttribute:MessageAttribute { let scheduleTime:Int32; let repeatPeriod:Int32?; init(scheduleTime:Int32,repeatPeriod:Int32?) { self.scheduleTime=scheduleTime; self.repeatPeriod=repeatPeriod };func withUpdatedRepeatPeriod(_ value:Int32?)->OutgoingScheduleInfoMessageAttribute {OutgoingScheduleInfoMessageAttribute(scheduleTime:scheduleTime,repeatPeriod:value)} }
final class OutgoingQuickReplyMessageAttribute:MessageAttribute {}
final class PaidStarsMessageAttribute:MessageAttribute {}
final class ReplyMessageAttribute:MessageAttribute {}
final class TextEntitiesMessageAttribute:MessageAttribute {}
final class RichTextMessageAttribute:MessageAttribute {}
final class WebpagePreviewMessageAttribute:MessageAttribute {}
final class InvertMediaMessageAttribute:MessageAttribute {}
struct ContentFlags:OptionSet { let rawValue:Int; static let disableLinkPreviews=ContentFlags(rawValue:1) }
final class OutgoingContentInfoMessageAttribute:MessageAttribute { init(flags:ContentFlags) {} }
struct NotificationFlags:OptionSet { let rawValue:Int; static let muted=NotificationFlags(rawValue:1) }
final class NotificationInfoMessageAttribute:MessageAttribute { let flags:NotificationFlags; init(flags:NotificationFlags) { self.flags=flags } }
enum RequestEditMessageMedia { case keep, update(AnyMediaReference) }

final class ReplyStoryAttribute:MessageAttribute { let storyId:Int=5 }
struct EngineMessageReplySubject {}
func resentReplySubject(_ attribute:ReplyMessageAttribute)->EngineMessageReplySubject { EngineMessageReplySubject() }
func filterMessageAttributesForOutgoingMessage(_ attributes:[MessageAttribute])->[MessageAttribute] { attributes }
struct UserFlags:OptionSet { let rawValue:Int; static let isPremium=UserFlags(rawValue:1) }
class User { var id=PeerId(0) }
final class TelegramUser:User { var flags:UserFlags=[] }
struct StoreMessageFlags:OptionSet { let rawValue:Int; init(rawValue:Int) { self.rawValue=rawValue }; init(_ value:StoreMessageFlags) { self=value }; static let Unsent=StoreMessageFlags(rawValue:1); static let Sending=StoreMessageFlags(rawValue:2); static let Failed=StoreMessageFlags(rawValue:4) }
struct StoreMessageForwardInfo { init(_ value:Int) {} }
enum StoreMessageId { case Id(MessageId) }
struct Message {
 let id:MessageId; var timestamp:Int32; var text:String; var attributes:[MessageAttribute]; var media:[Media]
 var scheduleRepeatPeriod:Int32? { attributes.compactMap{$0 as? OutgoingScheduleInfoMessageAttribute}.first?.repeatPeriod }
 var globallyUniqueId:Int64?=nil; var groupingKey:Int64?=nil; var threadId:Int64?=nil; var flags:StoreMessageFlags=[]; var tags=0; var globalTags=0; var localTags=0; var forwardInfo:Int?=nil; var author:User?=nil
}
final class StoreMessage {
 let id:StoreMessageId; let message:Message; var attributes:[MessageAttribute] { message.attributes }
 init(id:MessageId,customStableId:UInt32?,globallyUniqueId:Int64?,groupingKey:Int64?,threadId:Int64?,timestamp:Int32,flags:StoreMessageFlags,tags:Int,globalTags:Int,localTags:Int,forwardInfo:StoreMessageForwardInfo?,authorId:PeerId?,text:String,attributes:[MessageAttribute],media:[Media]) {
  self.id = .Id(id); self.message=Message(id:id,timestamp:timestamp,text:text,attributes:attributes,media:media,groupingKey:groupingKey,threadId:threadId,flags:flags)
 }
 init(_ message:Message) { id = .Id(message.id); self.message=message }
 func withUpdatedAttributes(_ attributes:[MessageAttribute])->StoreMessage { var m=message; m.attributes=attributes; return StoreMessage(m) }
}
enum PostboxUpdateMessage { case update(StoreMessage) }
final class PostboxEncoder { var value:PostboxCoding?; func encodeRootObject(_ value:PostboxCoding) { self.value=value }; func makeData()->Data { Data([value is Media ? 1 : 2]) } }
struct MemoryBuffer { let data:Data; init(data:Data) { self.data=data } }
final class PostboxDecoder { let data:Data; init(buffer:MemoryBuffer) { data=buffer.data }; func decodeRootObject()->PostboxCoding? { data.first==1 ? SampleMedia() : TextAttribute() } }
struct MessageReference { init(_ message:Message) {} }
enum AnyMediaReference { case standalone(media:Media), message(message:MessageReference,media:Media); var media:Media { switch self { case let .standalone(media),let .message(_,media):return media } } }
func augmentMediaWithReference(_ reference:AnyMediaReference)->Media { reference.media }

enum EnqueueMessage { case message(text:String,attributes:[MessageAttribute],inlineStickers:[MediaId:Media],mediaReference:AnyMediaReference?,threadId:Int64?,replyToMessageId:EngineMessageReplySubject?,replyToStoryId:Int?,localGroupingKey:Int64?,correlationId:Int64?,bubbleUpEmojiOrStickersets:[Int]) }
final class Transaction {
 var preferences:[ValueBoxKey:PreferencesEntry]=[:]; var messages:[MessageId:Message]=[:]; let user=TelegramUser(); var queued:[Message]=[]
 func getPreferencesEntry(key:ValueBoxKey)->PreferencesEntry? { preferences[key] }
 func updatePreferencesEntry(key:ValueBoxKey,_ f:(PreferencesEntry?)->PreferencesEntry?) { preferences[key]=f(preferences[key]) }
 func storeMediaIfNotPresent(media:Media) {}
 func getMessage(_ id:MessageId)->Message? { messages[id] }
 func getPeer(_ id:PeerId)->Any? { user }
 func updateMessage(_ id:MessageId,update:(Message)->PostboxUpdateMessage) { if let m=messages[id],case let .update(value)=update(m) { messages[id]=value.message } }
}
enum NoError:Error {}
struct Signal<V,E:Error> { let generate:()->[V]; static func complete()->Signal { Signal(generate:{[]}) }; func run()->[V] { generate() } }
infix operator |> : AdditionPrecedence
func |> <A,B>(a:A,b:(A)->B)->B { b(a) }
func mapToSignal<A,B,E>(_ f:@escaping(A)->Signal<B,E>)->(Signal<A,E>)->Signal<B,E> { { s in Signal(generate:{ s.run().flatMap { f($0).run() } }) } }
struct PreferencesView { let values:[ValueBoxKey:PreferencesEntry] }
final class Postbox { let t:Transaction; init(_ t:Transaction) { self.t=t }; func preferencesView(keys:[ValueBoxKey])->Signal<PreferencesView,NoError> { Signal(generate:{[PreferencesView(values:self.t.preferences)]}) }; func transaction<T>(_ f:@escaping(Transaction)->T)->Signal<T,NoError> { Signal(generate:{[f(self.t)]}) } }
final class Account { let stateManager:Int=0; let postbox:Postbox; init(_ t:Transaction) { postbox=Postbox(t) } }
func enqueueMessages(transaction:Transaction,account:Account,peerId:PeerId,messages:[(Bool,EnqueueMessage)])->[MessageId?] {
 messages.map { _,value in
  switch value { case let .message(text,attributes,_,_,threadId,_,_,_,_,_):
   let timestamp=Int32(Date().timeIntervalSince1970)
   let schedule=attributes.compactMap{$0 as? OutgoingScheduleInfoMessageAttribute}.first
   let id=MessageId(peerId:peerId,namespace:schedule == nil ? 0 : 3,id:Int32(transaction.queued.count+100))
   let m=Message(id:id,timestamp:schedule?.scheduleTime ?? timestamp,text:text,attributes:attributes,media:[],threadId:threadId)
   transaction.queued.append(m); transaction.messages[id]=m; rgCaptureStartupDailyMessages(transaction:transaction,ids:[id]); return id
  }
 }
}

enum DeletionType { case forEveryone }
func deleteMessagesInteractively(transaction:Transaction,stateManager:Int,postbox:Postbox,messageIds:[MessageId],type:DeletionType,removeIfPossiblyDelivered:Bool) { for id in messageIds { transaction.messages[id]=nil }; rgRemoveStartupDailyMessages(transaction:transaction,ids:messageIds) }
func _internal_sendScheduledMessageNowInteractively(postbox:Postbox,messageId:MessageId)->Signal<Never,NoError> { .complete() }
'''
source=source.replace("public func rgRunStartupDailyMessages", "func rgRunStartupDailyMessages")
tests=r'''
@main struct Tests {
 static func main() {
  let t=Transaction(), other=Transaction(), peer=PeerId(10), account=Account(t)
  var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(secondsFromGMT:0)!
  let now=Date(timeIntervalSince1970:1_700_000_000), today=RGRecurringSchedulePolicy.dayKey(now,calendar:calendar)
  let id=MessageId(peerId:peer,namespace:3,id:1)
  let attrs:[MessageAttribute]=[TextAttribute(),OutgoingScheduleInfoMessageAttribute(scheduleTime:Int32(now.timeIntervalSince1970),repeatPeriod:rgStartupDailyRepeatPeriod)]
  t.messages[id]=Message(id:id,timestamp:Int32(now.timeIntervalSince1970),text:"daily",attributes:attrs,media:[SampleMedia()],threadId:77,flags:[.Unsent])
  func check(_ v:Bool,_ m:String) { precondition(v,m) }
  rgCaptureStartupDailyMessages(transaction:t,ids:[id])
  check(t.queued.isEmpty,"creating the task does not send it")
  check(!t.messages[id]!.flags.contains(.Unsent),"task placeholder cannot upload to the Premium repeat API")
  rgCaptureStartupDailyMessages(transaction:t,ids:[id])
  check(rgDailyState(t).tasks.count==1,"capture is idempotent")
  check(rgDailyState(other).tasks.isEmpty,"account isolation")
  let reopened=Transaction(); reopened.preferences=t.preferences; reopened.messages=t.messages
  check(rgDailyState(reopened).tasks.count==1,"task survives serialized restart")
  _=rgRunStartupDailyMessages(transaction:t,account:account,now:now,calendar:calendar)
  check(t.queued.count==1 && t.queued[0].text=="daily" && t.queued[0].threadId==77,"first launch queues content and topic")
  check(t.queued[0].attributes.contains{($0 as? NotificationInfoMessageAttribute)?.flags.contains(.muted)==true},"startup send is silent")
  check(!t.queued[0].attributes.contains{$0 is OutgoingScheduleInfoMessageAttribute},"startup occurrence is an ordinary outgoing message")
  check(rgDailyState(t).tasks[0].lastSentDay==today,"day marker commits with outbox")
  _=rgRunStartupDailyMessages(transaction:t,account:account,now:now.addingTimeInterval(3600),calendar:calendar)
  check(t.queued.count==1,"same-day foreground resumes do not duplicate")
  _=rgRunStartupDailyMessages(transaction:t,account:account,now:now.addingTimeInterval(86400*5),calendar:calendar)
  check(t.queued.count==2,"skip missed dates and send once on next launch")
  let pending=t.queued.last!.id; t.messages[pending]!.flags=[.Unsent]
  _=rgRunStartupDailyMessages(transaction:t,account:account,now:now.addingTimeInterval(86400*6),calendar:calendar)
  check(t.queued.count==2,"offline outbox is reused on next-day launch")
  let delivered=MessageId(peerId:peer,namespace:0,id:900)
  t.messages[delivered]=Message(id:delivered,timestamp:Int32(now.timeIntervalSince1970),text:"daily",attributes:[],media:[SampleMedia()])
  rgApplyStartupDailyDelivery(transaction:t,previousId:pending,updatedId:delivered)
  check(rgDailyState(t).tasks[0].lastRunMessageId==delivered,"successful send retains resolved media reference")
  check(t.messages[id] != nil,"sending keeps editable task")
  check(rgEditStartupDailyMessage(transaction:t,messageId:id,text:"edited",media:.keep,entities:nil,richText:nil,inlineStickers:[:],webpagePreviewAttribute:nil,disableUrlPreview:false,scheduleInfoAttribute:nil,invertMediaAttribute:nil)==true,"task editor works locally")
  _=rgRunStartupDailyMessages(transaction:t,account:account,now:now.addingTimeInterval(86400*7),calendar:calendar)
  check(t.queued.last!.text=="edited","next launch uses edited text")
  rgRemoveStartupDailyMessages(transaction:t,ids:[id])
  _=rgRunStartupDailyMessages(transaction:t,account:account,now:now.addingTimeInterval(86400*8),calendar:calendar)
  check(t.queued.count==3 && rgDailyState(t).tasks.isEmpty,"deleting the task stops later launches")
  let converted=Transaction(), convertedAccount=Account(converted), cloud=MessageId(peerId:peer,namespace:2,id:44)
  converted.messages[cloud]=Message(id:cloud,timestamp:Int32(now.timeIntervalSince1970),text:"old schedule",attributes:[],media:[])
  check(rgConvertStartupDailyMessage(transaction:converted,account:convertedAccount,messageId:cloud,text:"converted daily",media:.keep,entities:nil,richText:nil,inlineStickers:[:],webpagePreviewAttribute:nil,disableUrlPreview:false,scheduleInfoAttribute:OutgoingScheduleInfoMessageAttribute(scheduleTime:Int32(now.timeIntervalSince1970),repeatPeriod:rgStartupDailyRepeatPeriod),invertMediaAttribute:nil)==true,"existing server schedule converts locally")
  check(converted.messages[cloud]==nil && rgDailyState(converted).tasks.count==1,"old server schedule is removed after task creation")
  let convertedId=rgDailyState(converted).tasks[0].messageId
  check(converted.messages[convertedId]?.text=="converted daily" && !converted.messages[convertedId]!.flags.contains(.Unsent),"converted task stays editable and out of server outbox")
  let native=Transaction(), nativeAccount=Account(native)
  for (index,period) in [86400,7*86400,14*86400,30*86400,91*86400,182*86400,365*86400].enumerated() {
   let nativeId=MessageId(peerId:peer,namespace:3,id:Int32(index+500))
   native.messages[nativeId]=Message(id:nativeId,timestamp:Int32(now.timeIntervalSince1970),text:"native",attributes:[OutgoingScheduleInfoMessageAttribute(scheduleTime:Int32(now.timeIntervalSince1970),repeatPeriod:Int32(period))],media:[],flags:[.Unsent])
   rgCaptureStartupDailyMessages(transaction:native,ids:[nativeId])
   check(native.messages[nativeId]!.flags.contains(.Unsent) && rgDailyState(native).tasks.isEmpty,"native repeat period remains in Telegram outbox")
  }
  let nativeCloud=MessageId(peerId:peer,namespace:2,id:900)
  native.messages[nativeCloud]=Message(id:nativeCloud,timestamp:Int32(now.timeIntervalSince1970),text:"Premium daily",attributes:[],media:[])
  check(rgConvertStartupDailyMessage(transaction:native,account:nativeAccount,messageId:nativeCloud,text:"Premium daily",media:.keep,entities:nil,richText:nil,inlineStickers:[:],webpagePreviewAttribute:nil,disableUrlPreview:false,scheduleInfoAttribute:OutgoingScheduleInfoMessageAttribute(scheduleTime:Int32(now.timeIntervalSince1970),repeatPeriod:86400),invertMediaAttribute:nil)==nil && native.messages[nativeCloud] != nil,"editing server daily does not convert or delete it")
  let legacy=Transaction(), legacyAccount=Account(legacy), legacyId=MessageId(peerId:peer,namespace:3,id:999)
  legacy.messages[legacyId]=Message(id:legacyId,timestamp:Int32(now.timeIntervalSince1970),text:"legacy",attributes:attrs,media:[],flags:[.Unsent])
  rgCaptureStartupDailyMessages(transaction:legacy,ids:[legacyId])
  legacy.messages[legacyId]!.attributes=[OutgoingScheduleInfoMessageAttribute(scheduleTime:Int32(now.timeIntervalSince1970),repeatPeriod:86400)]
  var legacyState=rgDailyState(legacy);legacyState.tasks[0].lastSentDay=today;rgSaveDailyState(legacy,legacyState)
  _=rgRunStartupDailyMessages(transaction:legacy,account:legacyAccount,now:now,calendar:calendar)
  check(legacy.messages[legacyId]?.scheduleRepeatPeriod==rgStartupDailyRepeatPeriod,"only a registered legacy local task gets the new marker")
  check(legacy.queued.isEmpty && rgDailyState(legacy).tasks[0].lastSentDay==today,"migration preserves the already-sent day")
  check(rgEditStartupDailyMessage(transaction:legacy,messageId:legacyId,text:"native again",media:.keep,entities:nil,richText:nil,inlineStickers:[:],webpagePreviewAttribute:nil,disableUrlPreview:false,scheduleInfoAttribute:OutgoingScheduleInfoMessageAttribute(scheduleTime:Int32(now.timeIntervalSince1970),repeatPeriod:86400),invertMediaAttribute:nil)==true && rgDailyState(legacy).tasks.isEmpty && legacy.messages[legacyId]!.flags.contains(.Unsent),"choosing native daily from a local task returns it to Telegram")
  print("Daily startup lifecycle: 31 checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-recurring-') as temp:
 p=Path(temp); (p/'main.swift').write_text(fixture+policy+source+tests)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-warnings-as-errors',str(p/'main.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)

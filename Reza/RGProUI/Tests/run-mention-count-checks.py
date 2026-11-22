from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[3]
s=(root/'submodules/TelegramCore/Sources/State/AccountViewTracker.swift').read_text()
a=s.index('                    // MARK: Regram — read all counters');b=s.index('\n                }\n            }',a)
body=s[a:b]
with tempfile.TemporaryDirectory(prefix='regram-mention-counts-') as d:
 p=Path(d)
 adapters='''
import Foundation
struct MessageTags:OptionSet { let rawValue:Int;static let unseenPersonalMessage=Self(rawValue:1);static let unseenReaction=Self(rawValue:2);static let unseenPollVote=Self(rawValue:4) }
enum PendingMessageActionType {case consumeUnseenPersonalMessage,readReactionOrPollVote}
struct MessageId:Hashable {let peerId:Int;let namespace:Int;let id:Int}
struct Message {let id:MessageId;let threadId:Int64?;let tags:MessageTags}
struct Action {let id:MessageId}
struct Summary {let count:Int32}
enum Namespaces {enum Message {static let Cloud=0}}
class Transaction {
 var messages:[Message]=[];var mentionActions:[Action]=[];var otherActions:[Action]=[]
 var counts:[Int:Int32]=[1:1,2:1,4:1]
 func getPendingMessageActions(type:PendingMessageActionType)->[Action] {type == .consumeUnseenPersonalMessage ? mentionActions:otherActions}
 func getMessage(_ id:MessageId)->Message? {messages.first{$0.id==id}}
 func getMessageTagSummary(peerId:Int,threadId:Int64?,tagMask:MessageTags,namespace:Int,customTag:Int?)->Summary? {Summary(count:counts[tagMask.rawValue] ?? 0)}
}
func counts(_ transaction:Transaction,peerId:Int,threadId:Int64?)->(mentionCount:Int32,reactionCount:Int32,pollVoteCount:Int32) {
'''
 tests='''
}
@main enum Tests {
 static func main() {
  let t=Transaction()
  let same=MessageId(peerId:1,namespace:0,id:1),otherTopic=MessageId(peerId:1,namespace:0,id:2),otherPeer=MessageId(peerId:2,namespace:0,id:3)
  t.messages=[Message(id:same,threadId:10,tags:[]),Message(id:otherTopic,threadId:20,tags:[.unseenPersonalMessage,.unseenPollVote]),Message(id:otherPeer,threadId:10,tags:[.unseenPersonalMessage,.unseenPollVote])]
  t.mentionActions=[Action(id:same),Action(id:otherTopic),Action(id:otherPeer)];t.otherActions=t.mentionActions
  let a=counts(t,peerId:1,threadId:10)
  precondition(a.mentionCount==1 && a.reactionCount==1 && a.pollVoteCount==1)
  t.messages[0]=Message(id:same,threadId:10,tags:[.unseenPersonalMessage,.unseenPollVote])
  let b=counts(t,peerId:1,threadId:10);precondition(b.mentionCount==0 && b.pollVoteCount==0 && b.reactionCount==1)
  t.counts[1]=2;t.counts[4]=2
  let c=counts(t,peerId:1,threadId:nil);precondition(c.mentionCount==0 && c.pollVoteCount==0)
  t.mentionActions=[];t.otherActions=[]
  let acknowledged=counts(t,peerId:1,threadId:10);precondition(acknowledged.mentionCount==2)
  print("Mention count checks passed with production transaction reducer: own topic, other peer/topic, cleared tags, actual pending mentions and new unread mentions.")
 }
}
'''
 (p/'Tests.swift').write_text(adapters+body+tests)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5',str(p/'Tests.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)

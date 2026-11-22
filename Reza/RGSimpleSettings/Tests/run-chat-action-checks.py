#!/usr/bin/env python3
"""Exercise production moderation initialization and forward visibility with UI/model adapters."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
sheet = (root / 'submodules/TelegramUI/Components/AdminUserActionsSheet/Sources/AdminUserActionsSheet.swift').read_text()
start = sheet.index('private func availableAdminUserActionOptionSections(')
end = sheet.index('\nprivate func adminUserActionsTitle(', start)
availability = sheet[start:end]
start = sheet.index('                if component.preselectModerationActions, case .chat = component.mode {')
end = sheet.index('\n                var (allowedParticipantRights,', start)
initialize = sheet[start:end]

moderation_adapters = '''
import Foundation
enum AdminUserActionOptionSection { case report, deleteAll, ban }
enum AdminUserActionsSheet { enum Mode { case chat, chatReaction, liveStream, monoforum } }
struct ChannelFlags: OptionSet { let rawValue: Int; static let isCreator = Self(rawValue: 1) }
enum Permission: Hashable { case deleteAllMessages, banMembers }
struct TelegramChannel {
 var flags: ChannelFlags = []
 var permissions: Set<Permission> = [.deleteAllMessages, .banMembers]
 func hasPermission(_ permission: Permission) -> Bool { permissions.contains(permission) }
}
enum EnginePeer { typealias Id = Int64; case channel(TelegramChannel), user(Id)
 var id: Id { if case let .user(id) = self { return id }; return 100 }
}
struct AdminInfo { let promotedBy: Int64 }
enum Participant { case creator; case member(Int64, Int, AdminInfo?, Int?, Int?, Int?) }
struct RenderedChannelParticipant { let peer: EnginePeer; let participant: Participant }
struct Account { let peerId: Int64 = 1 }
struct Context { let account = Account() }
struct Component {
 let context = Context()
 var chatPeer: EnginePeer = .channel(TelegramChannel())
 var peers = [RenderedChannelParticipant(peer: .user(2), participant: .member(2, 0, nil, nil, nil, nil))]
 var mode: AdminUserActionsSheet.Mode = .chat
 var preselectModerationActions = true
}
final class View {
 var component: Component?
 var optionReportSelectedPeers = Set<Int64>()
 var optionDeleteAllSelectedPeers = Set<Int64>()
 var optionDeleteAllReactionsSelectedPeers = Set<Int64>()
 var optionBanSelectedPeers = Set<Int64>()
 func update(_ component: Component) {
  if self.component == nil {
'''
moderation_tests = '''
  }
  self.component = component
 }
}
@main enum Tests {
 static func main() {
  var checks = 0
  func expect(_ condition: Bool) { precondition(condition); checks += 1 }
  var c = Component()
  let v = View(); v.update(c)
  expect(v.optionReportSelectedPeers == [2] && v.optionDeleteAllSelectedPeers == [2] && v.optionBanSelectedPeers == [2])
  expect(v.optionDeleteAllReactionsSelectedPeers == [2])
  v.optionReportSelectedPeers.removeAll(); v.optionBanSelectedPeers.removeAll(); v.update(c)
  expect(v.optionReportSelectedPeers.isEmpty && v.optionBanSelectedPeers.isEmpty)
  c.preselectModerationActions = false
  let off = View(); off.update(c)
  expect(off.optionReportSelectedPeers.isEmpty && off.optionDeleteAllSelectedPeers.isEmpty && off.optionBanSelectedPeers.isEmpty)
  c.preselectModerationActions = true
  for mode in [AdminUserActionsSheet.Mode.chatReaction, .liveStream, .monoforum] {
   c.mode = mode; let other = View(); other.update(c)
   expect(other.optionReportSelectedPeers.isEmpty && other.optionDeleteAllSelectedPeers.isEmpty && other.optionBanSelectedPeers.isEmpty)
  }
  c.mode = .chat
  c.chatPeer = .channel(TelegramChannel(permissions: [.deleteAllMessages]))
  let limited = View(); limited.update(c)
  expect(limited.optionDeleteAllSelectedPeers == [2] && limited.optionBanSelectedPeers.isEmpty)
  c.chatPeer = .channel(TelegramChannel(permissions: [.banMembers]))
  let noDeletion = View(); noDeletion.update(c)
  expect(noDeletion.optionReportSelectedPeers == [2] && noDeletion.optionDeleteAllSelectedPeers.isEmpty && noDeletion.optionBanSelectedPeers.isEmpty)
  c.chatPeer = .channel(TelegramChannel())
  for participant in [Participant.creator, .member(2, 0, AdminInfo(promotedBy: 3), nil, nil, nil)] {
   c.peers = [RenderedChannelParticipant(peer: .user(2), participant: participant)]
   let protected = View(); protected.update(c)
   expect(protected.optionBanSelectedPeers.isEmpty)
  }
  c.peers = [RenderedChannelParticipant(peer: .user(1), participant: .member(1, 0, nil, nil, nil, nil))]
  let own = View(); own.update(c)
  expect(own.optionReportSelectedPeers.isEmpty && own.optionDeleteAllSelectedPeers.isEmpty && own.optionBanSelectedPeers.isEmpty)
  c.peers = [2, 3].map { RenderedChannelParticipant(peer: .user(Int64($0)), participant: .member(Int64($0), 0, nil, nil, nil, nil)) }
  let multiple = View(); multiple.update(c)
  expect(multiple.optionReportSelectedPeers == [2, 3] && multiple.optionDeleteAllSelectedPeers == [2, 3] && multiple.optionBanSelectedPeers == [2, 3])
  print("Moderation initialization: \\(checks) checks passed (permissions, self, modes, multiple senders and user overrides).")
 }
}
'''

item = (root / 'submodules/TelegramUI/Components/Chat/ChatMessageItem/Sources/ChatMessageItem.swift').read_text()
forward = item[item.index('public func rgShouldHideMessageForwardButton('):].replace('public func ', 'func ', 1)
forward_adapters = '''
import Foundation
extension Int64 { func isRepliesOrSavedMessages(accountPeerId: Int64) -> Bool { self == -2 || self == accountPeerId } }
struct MessageId: Hashable { var peerId: Int64 = 100 }
final class TelegramChannel { var isMonoForum = true }
final class Message { var id = MessageId(); var adAttribute: Int?; var peers: [Int64: Any] = [:] }
struct Account { var peerId: Int64 = 1 }
struct Context { var account = Account() }
enum Kind { case hashTagSearch, other }
struct Contents { var kind: Kind }
enum Subject { case pinnedMessages, customChatContents(Contents) }
struct AssociatedData { var subject: Subject? }
struct Interaction { var summarizedMessageIds = Set<MessageId>() }
enum Location { case peer, replyThread }
final class ChatMessageItem {
 var message = Message(); var context = Context(); var associatedData = AssociatedData()
 var controllerInteraction = Interaction(); var chatLocation = Location.peer; var comments = false
}
func hasCommentButton(item: ChatMessageItem) -> Bool { item.comments }
'''
forward_tests = '''
@main enum Tests {
 static func main() {
  let item = ChatMessageItem(); var checks = 0
  func expect(_ result: Bool, enabled: Bool = true, comments: Bool = true) {
   precondition(rgShouldHideMessageForwardButton(item: item, isEnabled: enabled, commentsEnabled: comments) == result); checks += 1
  }
  expect(false, enabled: false); expect(true)
  item.message.adAttribute = 1; expect(false); item.message.adAttribute = nil
  item.message.id.peerId = 1; expect(false); item.message.id.peerId = -2; expect(false); item.message.id.peerId = 100
  item.associatedData.subject = .pinnedMessages; expect(false)
  item.associatedData.subject = .customChatContents(Contents(kind: .hashTagSearch)); expect(false)
  item.associatedData.subject = nil
  item.comments = true; expect(false); expect(true, comments: false); item.comments = false
  item.message.peers[100] = TelegramChannel(); expect(false)
  item.chatLocation = .replyThread; expect(true); item.message.peers.removeAll()
  item.controllerInteraction.summarizedMessageIds = [item.message.id]; expect(false)
  print("Forward button visibility: \\(checks) checks passed (forwarding, comments, navigation, ads and summaries).")
 }
}
'''

with tempfile.TemporaryDirectory(prefix='regram-chat-actions-') as directory:
    work = Path(directory)
    for name, source in [
        ('moderation', availability + moderation_adapters + initialize + moderation_tests),
        ('forward', forward_adapters + forward + forward_tests),
    ]:
        path = work / (name + '.swift')
        path.write_text(source)
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library', str(path), '-o', str(work / name)], check=True)
        subprocess.run([str(work / name)], check=True)

import Foundation

// Only dependencies are adapted; the runner compiles the production eligibility and delivery functions.
struct PeerId: Hashable, CustomStringConvertible {
    let value: Int64
    var namespace: Int32 { value >= 20 ? 2 : 0 }
    func toInt64() -> Int64 { value }
    var description: String { String(value) }
}
struct MessageId: Hashable { var peerId: PeerId; var namespace: Int32 = 0; var id: Int32 = 1 }
class Peer { let id: PeerId; var associatedPeerId: PeerId?; init(_ value: Int64) { id = PeerId(value: value) } }
final class TelegramGroup: Peer { }
final class TelegramUser: Peer { }
final class TelegramSecretChat: Peer { }
final class TelegramChannel: Peer {
    enum Info { case group, broadcast }
    enum Participation { case member, kicked, left }
    enum Flag { case isForum }
    var info = Info.group
    var participationStatus = Participation.member
    var flags: Set<Flag> = []
    var isMonoForum = false
}
struct Message {
    enum Flag { case Incoming }
    var id: MessageId
    var author: Peer?
    var flags: Set<Flag> = [.Incoming]
    var peers: [PeerId: Peer]
    var attributes: [Any] = []
    var media: [Any] = []
    var personal = false
    var threadId: Int64?
    var forwardInfo: ForwardInfo?
    var sourceReference: Int?
    var groupingKey: Int?
    var text = ""
    var rgTextContent: String { text }
    var index: Int { Int(id.id) }
}
struct ForwardInfo { enum Flag { case isImported }; var flags: Set<Flag> = [] }
final class NotificationInfoMessageAttribute { enum Flag { case muted }; let flags: Set<Flag> = [.muted] }
final class ReplyMessageAttribute { var threadMessageId: MessageId? }
final class TelegramMediaAction { enum Action { case groupMigratedToChannel, channelMigratedFromGroup, other }; var action = Action.other }
enum PeerMessageSound { case none, standard }
let defaultCloudPeerNotificationSound = PeerMessageSound.standard
struct MessageNotificationSettings { var sound = PeerMessageSound.standard; var notify = true; var display = true }
struct TelegramPeerNotificationSettings { var resolved = MessageNotificationSettings() }
struct MessageHistoryThreadData { var notificationSettings = TelegramPeerNotificationSettings() }
struct ThreadInfo { let data: StoredValue }
struct StoredValue { let value: Any; func get<T>(_ type: T.Type) -> T? { value as? T } }
struct GlobalNotificationSettings {
    struct Effective { var privateChats = MessageNotificationSettings(); var channels = MessageNotificationSettings(); var groupChats = MessageNotificationSettings() }
    var effective = Effective()
    static let defaultSettings = GlobalNotificationSettings()
}
func resolveNotificationSettings(list: [TelegramPeerNotificationSettings], defaultSettings: MessageNotificationSettings) -> (PeerMessageSound, Bool, Bool) {
    let settings = list.first?.resolved ?? defaultSettings
    return (settings.sound, settings.notify, settings.display)
}
struct ReadState { var read: Bool; func isIncomingMessageIndexRead(_ index: Int) -> Bool { read } }
final class Transaction {
    var message: Message
    var settings = TelegramPeerNotificationSettings(resolved: MessageNotificationSettings(sound: .none, notify: false, display: false))
    var read = false
    var group: [Message]?
    init(_ message: Message) { self.message = message }
    func getMessage(_ id: MessageId) -> Message? { message }
    func getPeer(_ id: PeerId) -> Peer? { message.peers[id] }
    func getPeerNotificationSettings(id: PeerId) -> Any? { settings }
    func getPreferencesEntry(key: String) -> StoredValue? { nil }
    func getMessageHistoryThreadInfo(peerId: PeerId, threadId: Int64) -> ThreadInfo? { nil }
    func getCombinedPeerReadState(_ id: PeerId) -> ReadState? { ReadState(read: read) }
    func getMessageForwardedGroup(_ id: MessageId) -> [Message]? { group }
    func getMessageGroup(_ id: MessageId) -> [Message]? { group }
}
enum Namespaces {
    enum Message { static let EphemeralLocal: Int32 = 1; static let allWelcomeMessages: [Int32] = [2] }
    enum Peer { static let CloudUser: Int32 = 0; static let SecretChat: Int32 = 1; static let CloudChannel: Int32 = 2 }
}
enum PreferencesKeys { static let globalNotifications = "global" }
final class Logger { static let shared = Logger(); func log(_ name: String, _ text: String) { } }
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var groupMemberReminderPreferences = RGGroupMemberReminderPreferences(senders: RGGroupMemberSelection(), groupHiddenSenders: RGGroupMemberSelection(), hiddenSenders: [], rules: [], disabledChats: [])
}

@main enum GroupNotificationDeliveryTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() {
        let account = PeerId(value: 11), group = TelegramChannel(21), sender = TelegramUser(31)
        var selection = RGGroupMemberSelection()
        selection.set(accountId: 11, groupId: 21, senderId: 31, selected: true)
        RGSimpleSettings.shared.groupMemberReminderPreferences = RGGroupMemberReminderPreferences(senders: selection, groupHiddenSenders: RGGroupMemberSelection(), hiddenSenders: [], rules: [], disabledChats: [])
        let message = Message(id: MessageId(peerId: group.id), author: sender, peers: [group.id: group], attributes: [NotificationInfoMessageAttribute()])
        let transaction = Transaction(message)
        func result(accountId: PeerId? = account) -> (messages: [Message], notify: Bool, sound: PeerMessageSound, displayContents: Bool, threadData: MessageHistoryThreadData?) {
            messagesForNotification(transaction: transaction, id: transaction.message.id, alwaysReturnMessage: false, accountPeerId: accountId)
        }
        let selected = result()
        expect(selected.messages.count == 1 && selected.notify && selected.sound == .standard, "A selected member must be delivered despite group and message muting")
        expect(!selected.displayContents, "Special alerts must retain preview privacy")
        expect(result(accountId: nil).messages.isEmpty && !result(accountId: PeerId(value: 12)).notify, "The old path and other accounts must retain ordinary muting")
        transaction.read = true
        expect(!result().notify, "Read messages must never regain notification eligibility")
        transaction.read = false
        group.participationStatus = .left
        expect(result().messages.isEmpty && !result().notify, "Leaving a group must still suppress delivery")
        group.participationStatus = .kicked
        expect(result().messages.isEmpty, "Removed members must not receive a revived group notification")
        group.participationStatus = .member
        transaction.message.author = TelegramUser(32)
        expect(result().messages.isEmpty, "Unselected members must retain ordinary muting")
        transaction.message = message
        transaction.message.flags = []
        expect(!result().notify, "Outgoing messages must not become member alerts")
        transaction.message = message
        transaction.message.media = [TelegramMediaAction()]
        expect(!result().notify, "Service updates must not become member alerts")
        transaction.message = message
        transaction.message.forwardInfo = ForwardInfo(flags: [.isImported])
        expect(!result().notify, "Historical imports must not become member alerts")
        transaction.message = message
        transaction.message.peers[group.id] = TelegramUser(21)
        expect(!result().notify, "A private chat must not qualify even with a matching stored identity")
        transaction.message = message
        transaction.message.peers[group.id] = TelegramGroup(21)
        expect(result().notify, "Basic groups and supergroups must both support selected-member alerts")
        transaction.message = message
        transaction.message.groupingKey = 1
        var next = message; next.id.id = 2
        transaction.group = [message, next]
        expect(result().messages.count == 2, "An album must retain its grouped notification contents")
        print("Group notification delivery checks passed: muted groups, silent posts, preview privacy, account isolation, read state, membership, service/import/private exclusions and albums")
    }
}

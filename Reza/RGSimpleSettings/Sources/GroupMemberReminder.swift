import Foundation

public struct RGGroupMemberReminderPreferences {
    public let senders: RGGroupMemberSelection
    public let groupHiddenSenders: RGGroupMemberSelection
    public let hiddenSenders: Set<Int64>
    public let rules: [RGMessageFilterRule]
    public let disabledChats: Set<Int64>

    public init(senders: RGGroupMemberSelection, groupHiddenSenders: RGGroupMemberSelection, hiddenSenders: Set<Int64>, rules: [RGMessageFilterRule], disabledChats: Set<Int64>) {
        self.senders = senders
        self.groupHiddenSenders = groupHiddenSenders
        self.hiddenSenders = hiddenSenders
        self.rules = rules
        self.disabledChats = disabledChats
    }

    /// Extensions may be reused after preferences change in the app. Take a fresh snapshot per push.
    public init(defaults: UserDefaults?) {
        self.init(
            senders: RGGroupMemberSelection(stored: defaults?.stringArray(forKey: "groupNotificationSenders") ?? []),
            groupHiddenSenders: RGGroupMemberSelection(stored: defaults?.stringArray(forKey: "groupHiddenSenders") ?? []),
            hiddenSenders: Set((defaults?.stringArray(forKey: "blockedPeerIds") ?? []).compactMap(Int64.init)),
            rules: RGMessageFilter.decode(defaults?.string(forKey: "messageFilterRules") ?? "[]"),
            disabledChats: Set((defaults?.stringArray(forKey: "messageFilterDisabledPeerIds") ?? []).compactMap(Int64.init))
        )
    }

    public func shouldRemind(accountId: Int64, groupId: Int64, senderId: Int64?, isIncoming: Bool, isGroup: Bool, isService: Bool, isImported: Bool, text: String) -> Bool {
        guard isIncoming, isGroup, !isService, !isImported, let senderId, senderId != accountId,
              self.senders.contains(accountId: accountId, groupId: groupId, senderId: senderId) else { return false }
        return !RGNotificationFilterPolicy.shouldHide(text: text, senderId: senderId, peerId: groupId, isIncoming: true, rules: self.rules, hiddenSenders: self.hiddenSenders, disabledChats: self.disabledChats, accountId: accountId, groupHiddenSenders: self.groupHiddenSenders)
    }
}

import Foundation

public enum RGNotificationFilterPolicy {
    public static func shouldHide(text: String, senderId: Int64?, peerId: Int64, isIncoming: Bool, rules: [RGMessageFilterRule], hiddenSenders: Set<Int64>, disabledChats: Set<Int64>) -> Bool {
        guard isIncoming else { return false }
        if let senderId, hiddenSenders.contains(senderId) { return true }
        return !disabledChats.contains(peerId) && RGMessageFilter.shouldHide(text: text, peerId: peerId, rules: rules)
    }
}

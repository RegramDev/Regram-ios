import Foundation

/// Local member selections are isolated by the signed-in account and the conversation.
public struct RGGroupMemberSelection: Equatable {
    public struct Member: Hashable {
        public let accountId: Int64
        public let groupId: Int64
        public let senderId: Int64

        public init(accountId: Int64, groupId: Int64, senderId: Int64) {
            self.accountId = accountId
            self.groupId = groupId
            self.senderId = senderId
        }

        fileprivate init?(_ stored: String) {
            let parts = stored.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, let accountId = Int64(parts[0]), let groupId = Int64(parts[1]), let senderId = Int64(parts[2]) else { return nil }
            self.init(accountId: accountId, groupId: groupId, senderId: senderId)
        }

        fileprivate var stored: String { "\(accountId):\(groupId):\(senderId)" }
    }

    private var members: Set<Member>
    public init(stored: [String] = []) { self.members = Set(stored.compactMap(Member.init)) }
    public var stored: [String] { self.members.map(\.stored).sorted() }
    public var isEmpty: Bool { self.members.isEmpty }

    public static func isValid(stored: [String]) -> Bool {
        stored.count <= 10000 && stored.allSatisfy { Member($0) != nil }
    }

    public func contains(accountId: Int64, groupId: Int64, senderId: Int64) -> Bool {
        self.members.contains(Member(accountId: accountId, groupId: groupId, senderId: senderId))
    }

    public func senderIds(accountId: Int64, groupId: Int64) -> Set<Int64> {
        Set(self.members.lazy.filter { $0.accountId == accountId && $0.groupId == groupId }.map(\.senderId))
    }

    public func groupIds(accountId: Int64) -> Set<Int64> {
        Set(self.members.lazy.filter { $0.accountId == accountId }.map(\.groupId))
    }

    public mutating func set(accountId: Int64, groupId: Int64, senderId: Int64, selected: Bool) {
        let member = Member(accountId: accountId, groupId: groupId, senderId: senderId)
        if selected { self.members.insert(member) } else { self.members.remove(member) }
    }
}

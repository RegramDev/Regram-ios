import Foundation

public final class RGTemporaryRevealState {
    private let lock = NSLock()
    private var entries: [String: (until: TimeInterval, ticket: UUID)] = [:]
    public init() {}
    public func begin(accountId: Int64, peerId: Int64, seconds: TimeInterval, now: TimeInterval) -> UUID {
        self.lock.lock(); defer { self.lock.unlock() }
        let ticket = UUID()
        self.entries[RGChatPreferences.key(accountId: accountId, peerId: peerId)] = (now + seconds, ticket)
        return ticket
    }
    @discardableResult public func end(accountId: Int64, peerId: Int64, ticket: UUID? = nil) -> Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        let key = RGChatPreferences.key(accountId: accountId, peerId: peerId)
        guard let entry = self.entries[key], ticket == nil || entry.ticket == ticket else { return false }
        self.entries.removeValue(forKey: key); return true
    }
    public func visiblePeerIds(accountId: Int64, now: TimeInterval) -> Set<Int64> {
        self.lock.lock(); defer { self.lock.unlock() }
        let prefix = "\(accountId):"
        return Set(self.entries.compactMap { key, entry in
            guard key.hasPrefix(prefix), entry.until > now else { return nil }
            return Int64(key.dropFirst(prefix.count))
        })
    }
}

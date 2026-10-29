// MARK: Regram — merge independently paginated group searches without skipping active groups.
import Foundation

struct RGCommonMessageOrder: Comparable, Hashable {
    let timestamp: Int32
    let peerId: Int64
    let namespace: Int32
    let messageId: Int32
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.peerId != rhs.peerId { return lhs.peerId < rhs.peerId }
        if lhs.namespace != rhs.namespace { return lhs.namespace < rhs.namespace }
        return lhs.messageId < rhs.messageId
    }
}

struct RGCommonGroupSearchStatus {
    let peerId: Int64
    var loaded = false
    var hasMore = true
    var loading = false
    var failed = false
    var oldest: RGCommonMessageOrder?
}

enum RGCommonGroupSearchPolicy {
    static let concurrency = 3
    static let pageSize = 30
    static let displayPageSize = 50

    // Match ProcessInfo.ThermalState raw values without requiring UIKit in pagination tests.
    static func requestLimit(lowPower: Bool, thermalState: Int) -> Int {
        if thermalState >= 3 { return 0 }
        if lowPower || thermalState >= 2 { return 1 }
        return thermalState == 1 ? 2 : concurrency
    }

    static func requestDelay(lowPower: Bool, thermalState: Int) -> TimeInterval {
        if thermalState >= 2 { return 1.0 }
        return lowPower || thermalState == 1 ? 0.6 : 0.2
    }

    static func nextGroups(_ statuses: [RGCommonGroupSearchStatus], orders: [RGCommonMessageOrder], visibleLimit: Int, selectedGroup: Int64?, concurrencyLimit: Int = concurrency) -> [Int64] {
        let groups = statuses.filter { selectedGroup == nil || $0.peerId == selectedGroup }
        let capacity = max(0, min(concurrency, concurrencyLimit) - statuses.filter(\.loading).count)
        let sorted = orders.sorted(by: >)
        let limit = max(1, visibleLimit)
        let cutoff = sorted.count >= limit ? sorted[limit - 1] : nil
        return groups.filter { group in
            guard !group.loading, !group.failed, group.hasMore else { return false }
            if !group.loaded || cutoff == nil { return true }
            // Fetch again while this group's unseen tail could precede the visible cutoff.
            return group.oldest.map { $0 >= cutoff! } ?? true
        }.sorted { lhs, rhs in
            if lhs.loaded != rhs.loaded { return !lhs.loaded }
            if lhs.oldest != rhs.oldest { return (lhs.oldest ?? maximumOrder) > (rhs.oldest ?? maximumOrder) }
            return lhs.peerId < rhs.peerId
        }.prefix(capacity).map(\.peerId)
    }

    private static let maximumOrder = RGCommonMessageOrder(timestamp: .max, peerId: .max, namespace: .max, messageId: .max)
}

// Plain result rows do not expose spoiler text before the user opens the message.
enum RGCommonGroupPreview {
    static func text(_ text: String, spoilers: [Range<Int>], reveal: Bool) -> String {
        let preview = NSMutableString(string: String(text.prefix(600)))
        if !reveal {
            for range in spoilers.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                let lower = max(0, range.lowerBound), upper = min(preview.length, range.upperBound)
                if lower < upper { preview.replaceCharacters(in: NSRange(location: lower, length: upper - lower), with: String(repeating: "▪", count: upper - lower)) }
            }
        }
        return preview as String
    }
}

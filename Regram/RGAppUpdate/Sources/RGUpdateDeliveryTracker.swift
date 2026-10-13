// MARK: Regram — only a complete file handoff permits closing the update host.
import Foundation

struct RGUpdateDeliveryTracker {
    let size: UInt64
    private(set) var isComplete = false
    private var ranges: [Range<UInt64>] = []

    mutating func record(_ range: Range<UInt64>) -> Bool {
        guard !isComplete, !range.isEmpty, range.upperBound <= size else { return false }
        var merged = range
        var next: [Range<UInt64>] = []
        for existing in ranges {
            if existing.upperBound < merged.lowerBound { next.append(existing) }
            else if merged.upperBound < existing.lowerBound { next.append(merged); merged = existing }
            else { merged = min(existing.lowerBound, merged.lowerBound)..<max(existing.upperBound, merged.upperBound) }
        }
        next.append(merged)
        ranges = next
        isComplete = ranges.count == 1 && ranges[0] == 0..<size
        return isComplete
    }
}

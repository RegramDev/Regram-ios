import Foundation
@main struct UpdateDeliveryTrackerTests {
    static func main() {
        var tracker = RGUpdateDeliveryTracker(size: 100)
        assert(!tracker.record(0..<0))
        assert(!tracker.record(90..<101))
        assert(!tracker.record(20..<40))
        assert(!tracker.record(0..<10))
        assert(!tracker.record(80..<100))
        assert(!tracker.record(40..<80))
        assert(!tracker.isComplete, "A gap must prevent quitting")
        assert(!tracker.record(5..<15))
        assert(tracker.record(15..<20), "Overlapping and adjacent ranges must cover the complete file")
        assert(tracker.isComplete)
        assert(!tracker.record(0..<100), "Completion must only be reported once")
        var reverse = RGUpdateDeliveryTracker(size: 1024)
        for lower in stride(from: 960, through: 64, by: -64) { assert(!reverse.record(UInt64(lower)..<UInt64(lower + 64))) }
        assert(reverse.record(0..<64))
        print("Delivery tracking passed: out-of-order ranges, overlap, gaps, invalid bounds and a single complete handoff.")
    }
}

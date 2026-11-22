import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
private func near(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.0001 }

@main enum DiagnosticsTests {
    static func main() {
        let stats = RGTransferStatistics()
        expect(stats.snapshot(now: 10).receivedBytes == 0, "New session must start at zero")
        stats.recordReceived(byteCount: 3000, now: 10)
        expect(near(stats.snapshot(now: 10).bytesPerSecond, 1000), "A burst must use the full three-second divisor")
        stats.recordReceived(byteCount: 1500, now: 11)
        expect(near(stats.snapshot(now: 12).bytesPerSecond, 1500), "Rate must include all bytes in the trailing window")
        expect(near(stats.snapshot(now: 13).bytesPerSecond, 500), "Bytes exactly three seconds old must expire")
        expect(stats.snapshot(now: 14).bytesPerSecond == 0 && stats.snapshot(now: 14).receivedBytes == 4500, "Idle must preserve total and reset rate")
        stats.recordReceived(byteCount: 100, now: 13.9)
        expect(stats.snapshot(now: 14).receivedBytes == 4600, "Out-of-order parallel samples must not lose bytes")
        stats.recordReceived(byteCount: -1, now: 14)
        stats.recordReceived(byteCount: 0, now: 14)
        stats.recordReceived(byteCount: 100, now: .nan)
        expect(stats.snapshot(now: 14).receivedBytes == 4600, "Invalid samples must be ignored")
        let busy = RGTransferStatistics()
        for index in 0..<10000 { busy.recordReceived(byteCount: 64, now: 20 + Double(index) / 10000) }
        expect(busy.snapshot(now: 21).receivedBytes == 640000 && near(busy.snapshot(now: 21).bytesPerSecond, 640000.0 / 3), "High event counts must not drop rate samples")
        let remaining = (0..<10000).filter { 23.6 - (20 + Double($0) / 10000) < RGTransferStatistics.rateInterval }.count
        expect(near(busy.snapshot(now: 23.6).bytesPerSecond, Double(remaining * 64) / 3), "Queue compaction must preserve unexpired bytes")
        expect(busy.snapshot(now: 30).bytesPerSecond == 0, "Large queues must expire completely")
        let concurrent = RGTransferStatistics()
        DispatchQueue.concurrentPerform(iterations: 10000) { _ in concurrent.recordReceived(byteCount: 100, now: 50) }
        expect(concurrent.snapshot(now: 51).receivedBytes == 1000000, "Concurrent downloads must accumulate safely")
        let saturated = RGTransferStatistics()
        for _ in 0..<10 { saturated.recordReceived(byteCount: Int.max, now: 60) }
        expect(saturated.snapshot(now: 60).receivedBytes == Int64.max && saturated.snapshot(now: 60).roundedBytesPerSecond == Int64.max, "Extreme counters must not overflow UI conversions")

        var messages = Set<String>()
        var clockCalls = 0
        let original = RGMessageFilterRule(pattern: "sample", peerIds: [99])
        let result = RGFilterBenchmark.measure(rules: [original], now: {
            defer { clockCalls += 1 }; return clockCalls == 0 ? 40 : 40.15
        }, match: { message, rules in
            messages.insert(message)
            expect(rules.count == 1 && rules[0].peerIds.isEmpty, "Benchmark must remove only chat restrictions")
            return false
        })
        expect(RGFilterBenchmark.messageCount == 100 && messages.count == 100, "Every test must evaluate exactly 100 distinct messages")
        expect(original.peerIds == [99] && near(result!.averageMilliseconds, 1.5), "Benchmark must preserve real rules and calculate per-message time")
        var evaluated = 0
        let cancelled = RGFilterBenchmark.measure(rules: [], shouldContinue: { evaluated < 7 }, match: { _, _ in evaluated += 1; return false })
        expect(cancelled == nil && evaluated == 7, "Leaving the page must cancel between messages")
        let session = RGFilterBenchmarkSession()
        let first = session.begin()
        let restarted = session.begin()
        expect(!session.isActive(first) && session.isActive(restarted), "Second tap must replace the running test")
        session.cancel()
        let second = session.begin()
        expect(!session.finish(first) && session.isActive(second), "Late completion must not replace a newer test")
        expect(session.finish(second), "Current test must complete normally")
        let third = session.begin()
        expect(session.isActive(third) && !session.isActive(second), "A completed test must start fresh on the next tap")
        print("Diagnostics checks passed: exact rolling window, high-volume/concurrent counters, 100-message benchmark, restart taps and stale completion cancellation")
    }
}

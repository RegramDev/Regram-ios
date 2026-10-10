import Foundation

/// Payload bytes accepted by Telegram's multipart downloader, across signed-in accounts. This is
/// a short moving estimate, not protocol overhead, cached reads or a promised acceleration factor.
public final class RGTransferStatistics {
    public struct Snapshot {
        public let receivedBytes: Int64
        public let bytesPerSecond: Double
    }
    public static let shared = RGTransferStatistics()
    private let lock = NSLock()
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    private var total: Int64 = 0
    public init() {}
    public func recordReceived(byteCount: Int, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard byteCount > 0, now.isFinite else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        let bytes = Int64(byteCount)
        self.total = self.total > Int64.max - bytes ? Int64.max : self.total + bytes
        self.samples.removeAll { now - $0.time > 3 || $0.time > now }
        if self.samples.count >= 4096 { self.samples.removeFirst() }
        self.samples.append((now, bytes))
    }
    public func snapshot(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Snapshot {
        self.lock.lock(); defer { self.lock.unlock() }
        guard now.isFinite else { return Snapshot(receivedBytes: self.total, bytesPerSecond: 0) }
        self.samples.removeAll { now - $0.time > 3 || $0.time > now }
        let bytes = self.samples.reduce(0.0) { $0 + Double($1.bytes) }
        let duration = self.samples.first.map { max(1, min(3, now - $0.time)) } ?? 1
        return Snapshot(receivedBytes: self.total, bytesPerSecond: bytes / duration)
    }
}

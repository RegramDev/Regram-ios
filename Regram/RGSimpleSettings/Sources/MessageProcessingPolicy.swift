// MARK: Regram — bounded, versioned verdicts and generation-safe translation work.
import Foundation

public final class RGMessageVerdictCache<Key: Hashable, Value> {
    private let lock = NSLock()
    private let capacity: Int
    private var values: [Key: (version: UInt32, value: Value)] = [:]
    private var order: [Key] = []
    public init(capacity: Int = 4096) { self.capacity = max(1, capacity) }
    public func value(for key: Key, version: UInt32) -> Value? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let entry = self.values[key], entry.version == version else { return nil }
        return entry.value
    }
    public func store(_ value: Value, for key: Key, version: UInt32) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.values[key] == nil { self.order.append(key) }
        self.values[key] = (version, value)
        while self.order.count > self.capacity { self.values.removeValue(forKey: self.order.removeFirst()) }
    }
}

public struct RGTranslationWorkState<Key: Hashable> {
    private var generation: UInt64 = 0
    private var pending: [Key: (language: String, generation: UInt64)] = [:]
    private var retryAfter: [Key: (language: String, deadline: Double)] = [:]
    public init() {}
    public func canSchedule(_ key: Key, language: String, now: Double) -> Bool {
        if self.pending[key]?.language == language { return false }
        if let retry = self.retryAfter[key], retry.language == language && now < retry.deadline { return false }
        return true
    }
    public mutating func begin(_ keys: [Key], language: String, now: Double) -> (generation: UInt64, keys: [Key]) {
        var seen = Set<Key>()
        let accepted = keys.filter { seen.insert($0).inserted && self.canSchedule($0, language: language, now: now) }
        self.generation &+= 1
        for key in accepted { self.pending[key] = (language, self.generation) }
        return (self.generation, accepted)
    }
    public mutating func finish(_ keys: [Key], language: String, generation: UInt64, now: Double) {
        for key in keys where self.pending[key]?.generation == generation && self.pending[key]?.language == language {
            self.pending.removeValue(forKey: key)
            self.retryAfter[key] = (language, now + 1.0)
        }
        // Completed messages do not grow an unbounded per-chat retry table.
        if self.retryAfter.count > 4096 { self.retryAfter = self.retryAfter.filter { $0.value.deadline > now } }
    }
    public mutating func reset() {
        self.generation &+= 1
        self.pending.removeAll()
        self.retryAfter.removeAll()
    }
}

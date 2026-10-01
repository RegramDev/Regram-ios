// MARK: Regram — policies shared by the media loading experiment and its regression checks.
import Foundation

public enum RGMediaLoadingPolicy {
    public static let preloadCount = 6
    public static let removalGraceInterval = 1.5
    public static let maximumPendingRemovals = 3

    #if REGRAM_MEDIA_LOADING_EXPERIMENT
    public static let enabledByDefault = true
    #else
    public static let enabledByDefault = false
    #endif

    public static let settingsChanged = Notification.Name("Regram.MediaLoadingExperimentChanged")

    // The input order is the existing FetchManager priority order. Reserve one manual
    // download and bound automatic work, giving the current screen precedence.
    public static func selectedResources(candidates: [RGMediaFetchCandidate], visible: [String], preload: [String], streaming: Set<String>) -> Set<String> {
        let eligible = candidates.filter { !$0.isPaused }
        var result = Set<String>()
        if let manual = eligible.first(where: { $0.isUserInitiated }) {
            result.insert(manual.resourceId)
        }
        let visibleRanks = Dictionary(visible.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let preloadRanks = Dictionary(preload.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let ordered = eligible.enumerated().filter { !$0.element.isUserInitiated }.sorted { lhs, rhs in
            func rank(_ candidate: RGMediaFetchCandidate) -> (Int, Int) {
                if streaming.contains(candidate.resourceId) { return (0, 0) }
                if let index = visibleRanks[candidate.resourceId] { return (1, index) }
                if let index = preloadRanks[candidate.resourceId] { return (2, index) }
                return (candidate.isForegroundPrefetch ? 3 : 4, 0)
            }
            let l = rank(lhs.element)
            let r = rank(rhs.element)
            return l == r ? lhs.offset < rhs.offset : l < r
        }
        // Direct streaming also bypasses FetchManager: leave it bandwidth headroom.
        let limit = streaming.isEmpty ? 2 : 1
        var automaticCount = 0
        for (_, candidate) in ordered {
            guard !result.contains(candidate.resourceId) else { continue }
            if !streaming.isEmpty && !streaming.contains(candidate.resourceId) && visibleRanks[candidate.resourceId] == nil {
                continue
            }
            guard automaticCount < limit else { break }
            result.insert(candidate.resourceId)
            automaticCount += 1
        }
        return result
    }
}

public struct RGMediaFetchCandidate {
    public let resourceId: String
    public let isUserInitiated: Bool
    public let isForegroundPrefetch: Bool
    public let isPaused: Bool

    public init(resourceId: String, isUserInitiated: Bool = false, isForegroundPrefetch: Bool = false, isPaused: Bool = false) {
        self.resourceId = resourceId
        self.isUserInitiated = isUserInitiated
        self.isForegroundPrefetch = isForegroundPrefetch
        self.isPaused = isPaused
    }
}

// A covered chat must not erase the foreground chat's priorities, and two players
// sharing a resource must release their references independently.
public struct RGMediaPriorityState {
    private var screens: [Int64: (visible: [String], preload: [String])] = [:]
    private var owners: [Int64] = []
    private var streamingReferences: [String: Int] = [:]

    public init() {}

    public var visible: [String] { return self.owners.last.flatMap { self.screens[$0]?.visible } ?? [] }
    public var preload: [String] { return self.owners.last.flatMap { self.screens[$0]?.preload } ?? [] }
    public var streaming: Set<String> { return Set(self.streamingReferences.keys) }

    public mutating func updateScreen(owner: Int64, visible: [String], preload: [String]) -> Bool {
        func unique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { seen.insert($0).inserted }
        }
        let visible = unique(visible)
        let preload = unique(preload)
        if let previous = self.screens[owner], previous.visible == visible, previous.preload == preload { return false }
        if self.screens[owner] == nil && visible.isEmpty && preload.isEmpty { return false }
        self.owners.removeAll(where: { $0 == owner })
        if visible.isEmpty && preload.isEmpty { self.screens.removeValue(forKey: owner) }
        else {
            self.screens[owner] = (visible, preload)
            self.owners.append(owner)
        }
        return true
    }

    public mutating func acquireStreaming(_ resourceId: String) {
        self.streamingReferences[resourceId, default: 0] += 1
    }

    public mutating func releaseStreaming(_ resourceId: String) {
        guard let count = self.streamingReferences[resourceId] else { return }
        if count == 1 { self.streamingReferences.removeValue(forKey: resourceId) }
        else { self.streamingReferences[resourceId] = count - 1 }
    }

    public func weights(enabled: Bool) -> [String: Int] {
        guard enabled else { return [:] }
        var weights: [String: Int] = [:]
        for id in self.preload { weights[id] = 10 }
        for (index, id) in self.visible.enumerated() { weights[id] = max(20, 60 - index) }
        for id in self.streaming { weights[id] = 100 }
        return weights
    }
}

public struct RGMediaRemovalTicket: Equatable {
    public let generation: UInt64
    public let deadline: Double
}

// Timer callbacks carry a generation so a rescued/replaced task cannot be removed by
// an old callback. This state contains no timers or account data and is clock-testable.
public struct RGMediaPreloadRetention<Key: Hashable> {
    public private(set) var pending: [Key: RGMediaRemovalTicket] = [:]
    private var order: [Key] = []
    private var generation: UInt64 = 0

    public init() {}

    public mutating func deferRemoval(_ key: Key, now: Double) -> (ticket: RGMediaRemovalTicket, evicted: [Key]) {
        if let ticket = self.pending[key] { return (ticket, []) }
        self.generation &+= 1
        let ticket = RGMediaRemovalTicket(generation: self.generation, deadline: now + RGMediaLoadingPolicy.removalGraceInterval)
        self.pending[key] = ticket
        self.order.append(key)
        var evicted: [Key] = []
        while self.order.count > RGMediaLoadingPolicy.maximumPendingRemovals {
            let oldest = self.order.removeFirst()
            self.pending.removeValue(forKey: oldest)
            evicted.append(oldest)
        }
        return (ticket, evicted)
    }

    public mutating func rescue(_ key: Key) {
        self.pending.removeValue(forKey: key)
        self.order.removeAll(where: { $0 == key })
    }

    public mutating func expire(_ key: Key, ticket: RGMediaRemovalTicket, now: Double) -> Bool {
        guard self.pending[key] == ticket, now >= ticket.deadline else { return false }
        self.rescue(key)
        return true
    }

    public mutating func reset() {
        self.pending.removeAll()
        self.order.removeAll()
    }
}

// MARK: Regram — shared playback/retention policies; callers own UI and timers.
import Foundation

public struct RGInlineVideoCandidate {
    public let id: Int64
    public let stableId: Int64
    public let eligible: Bool
    public let visibleFraction: Double
    public let distanceFromCenter: Double
    public let userInitiated: Bool
    public let hasSound: Bool
    public let alreadyAdmitted: Bool

    public init(id: Int64, stableId: Int64, eligible: Bool, visibleFraction: Double, distanceFromCenter: Double, userInitiated: Bool, hasSound: Bool, alreadyAdmitted: Bool) {
        self.id = id
        self.stableId = stableId
        self.eligible = eligible
        self.visibleFraction = visibleFraction
        self.distanceFromCenter = distanceFromCenter
        self.userInitiated = userInitiated
        self.hasSound = hasSound
        self.alreadyAdmitted = alreadyAdmitted
    }
}

public extension RGMediaLoadingPolicy {
    static let maximumInlinePlayers = 2
    static let maximumInlineHolders = 3
    static let maximumRetainedInlineHolders = 1
    static let galleryReturnFallbackInterval = 0.1
    static let inlineVideoCapacityChanged = Notification.Name("Regram.InlineVideoCapacityChanged")

    static func selectedInlineVideos(_ candidates: [RGInlineVideoCandidate], active: Bool, thermalCritical: Bool, limit: Int = maximumInlinePlayers) -> [Int64] {
        guard active, !thermalCritical, limit > 0 else { return [] }
        return candidates.filter { $0.eligible && $0.visibleFraction > 0 }.sorted { lhs, rhs in
            if lhs.userInitiated != rhs.userInitiated { return lhs.userInitiated }
            if lhs.hasSound != rhs.hasSound { return lhs.hasSound }
            if lhs.distanceFromCenter != rhs.distanceFromCenter { return lhs.distanceFromCenter < rhs.distanceFromCenter }
            if lhs.visibleFraction != rhs.visibleFraction { return lhs.visibleFraction > rhs.visibleFraction }
            if lhs.alreadyAdmitted != rhs.alreadyAdmitted { return lhs.alreadyAdmitted }
            if lhs.stableId != rhs.stableId { return lhs.stableId < rhs.stableId }
            return lhs.id < rhs.id
        }.prefix(limit).map(\.id)
    }
}

// Detached players are distinct from retained prefetch jobs. The same policy is
// used by the manager and tests, including capacity and session handoff eviction.
public struct RGInlineVideoRetention<Key: Hashable> {
    private var entries: [(id: Key, session: Int64)] = []
    private var preferred: [Int64: Key] = [:]
    public init() {}
    public var ids: [Key] { return self.entries.map(\.id) }

    public mutating func take(_ id: Key) {
        self.entries.removeAll { $0.id == id }
    }

    public mutating func prefer(_ id: Key?, session: Int64) -> [Key] {
        self.preferred[session] = id
        guard let id else { return [] }
        let evicted = self.entries.filter { $0.session == session && $0.id != id }.map(\.id)
        self.entries.removeAll { evicted.contains($0.id) }
        return evicted
    }

    public mutating func retain(_ id: Key, session: Int64, activeInlineCount: Int) -> [Key] {
        self.take(id)
        guard self.preferred[session] == nil || self.preferred[session] == id else { return [id] }
        let sameSession = self.entries.filter { $0.session == session }.map(\.id)
        self.entries.removeAll { $0.session == session }
        self.entries.append((id, session))
        return sameSession + self.trim(activeInlineCount: activeInlineCount)
    }

    public mutating func trim(activeInlineCount: Int) -> [Key] {
        let limit = min(RGMediaLoadingPolicy.maximumRetainedInlineHolders, max(0, RGMediaLoadingPolicy.maximumInlineHolders - activeInlineCount))
        var evicted: [Key] = []
        while self.entries.count > limit { evicted.append(self.entries.removeFirst().id) }
        return evicted
    }

    public mutating func end(session: Int64) -> [Key] {
        self.preferred.removeValue(forKey: session)
        let evicted = self.entries.filter { $0.session == session }.map(\.id)
        self.entries.removeAll { $0.session == session }
        return evicted
    }

    public mutating func reset() -> [Key] {
        let ids = self.ids
        self.entries.removeAll()
        self.preferred.removeAll()
        return ids
    }
}

// A foreground player owns a *set* of HLS playlist/quality IDs. Quality switches
// must not accidentally defer their own fragments. Audible/manual owners win;
// otherwise the most recently admitted owner gets the remote streaming lane.
public struct RGStreamingAdmissionState {
    private var owners: [Int64: (resources: Set<String>, userInitiated: Bool, generation: UInt64)] = [:]
    private var order: [Int64] = []
    private var generation: UInt64 = 0
    private var preferredOwners: [Int64: Int64] = [:]
    private var preferredSessions: [Int64] = []
    public init() {}
    public var selectedResources: Set<String> {
        let preferred = self.preferredSessions.reversed().compactMap { self.preferredOwners[$0] }.first { self.owners[$0] != nil }
        let owner = self.order.reversed().first { self.owners[$0]?.userInitiated == true } ?? preferred ?? self.order.last
        return owner.flatMap { self.owners[$0]?.resources } ?? []
    }
    @discardableResult public mutating func acquire(owner: Int64, resources: [String], userInitiated: Bool) -> UInt64 {
        self.generation &+= 1
        self.owners[owner] = (Set(resources), userInitiated, self.generation)
        self.order.removeAll { $0 == owner }
        self.order.append(owner)
        return self.generation
    }
    public mutating func release(owner: Int64, generation: UInt64? = nil) {
        if let generation, self.owners[owner]?.generation != generation { return }
        self.owners.removeValue(forKey: owner)
        self.order.removeAll { $0 == owner }
    }
    @discardableResult public mutating func prefer(owner: Int64?, session: Int64) -> Bool {
        if self.preferredOwners[session] == owner && (owner == nil || self.preferredSessions.last == session) { return false }
        self.preferredOwners[session] = owner
        self.preferredSessions.removeAll { $0 == session }
        if owner != nil { self.preferredSessions.append(session) }
        return true
    }
}

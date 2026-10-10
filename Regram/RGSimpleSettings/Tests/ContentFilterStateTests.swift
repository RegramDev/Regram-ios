import Foundation

// External engine/settings adapters only. The runner compiles the production cache/state body.
public struct EnginePeer {
    public struct Id: Hashable { let value: Int64; public func toInt64() -> Int64 { value } }
    public let id: Id
}
public struct EngineMessage {
    public struct Id: Hashable { public let peerId: EnginePeer.Id; public let namespace: Int32; public let id: Int32 }
    public let id: Id
    public let stableVersion: UInt32
    public let text: String
    public let author: EnginePeer?
    public func effectivelyIncoming(_ id: EnginePeer.Id) -> Bool { self.author?.id != id }
}
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var ephemeralStatus = 2
    var messageFilterRules: [RGMessageFilterRule] = []
    var blockedPeerIds: Set<Int64> = []
    var messageFilterDisabledPeerIds: Set<Int64> = []
    var contentFilterGeneration = 0
    var revealedPeerIds: Set<Int64> = []
    func temporarilyVisiblePeerIds(accountId: Int64) -> Set<Int64> { self.revealedPeerIds }
}

@main enum ContentFilterStateTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() {
        let settings = RGSimpleSettings.shared
        let peer = EnginePeer.Id(value: 1), account = EnginePeer.Id(value: 2)
        let id = EngineMessage.Id(peerId: peer, namespace: 0, id: 1)
        var disabled = RGMessageFilterRule(pattern: "blocked", isEnabled: false)
        func state() -> RGContentFilterState { settings.contentFilterGeneration += 1; return RGContentFilterState(accountPeerId: account) }
        func hidden(_ filter: RGContentFilterState, text: String, version: UInt32 = 1) -> Bool { filter.shouldHide(messageId: id, stableVersion: version, text: text, authorId: peer, isIncoming: true) }
        settings.messageFilterRules = [disabled]
        expect(!hidden(state(), text: "blocked"), "Disabled rules must keep incoming messages visible")
        disabled.isEnabled = true
        settings.messageFilterRules = [disabled]
        let enabled = state()
        expect(hidden(enabled, text: "blocked"), "Enabling a rule must invalidate the cached visible result")
        expect(!hidden(enabled, text: "allowed", version: 2), "Same-length edits must invalidate the hidden result")
        settings.messageFilterRules.append(RGMessageFilterRule(pattern: "blocked", isException: true))
        let kept = state()
        expect(!hidden(kept, text: "blocked", version: 2), "Keep rules must invalidate cached hide verdicts")
        _ = hidden(enabled, text: "blocked", version: 3)
        expect(!hidden(kept, text: "blocked", version: 2), "Late results from older rule generations must not poison the current cache")
        settings.blockedPeerIds = [1]
        settings.messageFilterDisabledPeerIds = [1]
        expect(hidden(state(), text: "blocked"), "Hidden senders stay hidden despite keep rules or chat rule disablement")
        settings.revealedPeerIds = [1]
        expect(!hidden(state(), text: "blocked"), "Explicit temporary reveal must recover hidden-sender and keyword content")
        settings.revealedPeerIds = []
        expect(hidden(state(), text: "blocked"), "Ending temporary reveal must restore filtering and invalidate visible cache")
        settings.blockedPeerIds = [2]
        let selfHidden = state()
        expect(!selfHidden.shouldHide(text: "blocked", authorId: account, peerId: peer, isIncoming: false), "Your own outgoing messages must stay visible")
        settings.blockedPeerIds = []
        settings.messageFilterDisabledPeerIds = []
        settings.messageFilterRules = [disabled]
        let eviction = state()
        for index in 0..<8300 {
            let messageId = EngineMessage.Id(peerId: peer, namespace: 0, id: Int32(index))
            expect(eviction.shouldHide(messageId: messageId, stableVersion: 1, text: "blocked", authorId: peer, isIncoming: true), "Bounded cache eviction must retain matching behavior")
        }
        expect(hidden(eviction, text: "blocked", version: 10), "An evicted/edited message must be recomputed correctly")
        print("Content filter state checks passed: production verdict cache, enabled/keep generation changes, same-length edits, late passes, hidden senders, outgoing messages and 8300-entry eviction")
    }
}

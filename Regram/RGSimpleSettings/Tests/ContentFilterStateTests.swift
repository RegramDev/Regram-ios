import Foundation

// External engine/settings adapters only. The runner compiles the production cache/state body.
public struct EnginePeer {
    public struct Id: Hashable { let value: Int64; public func toInt64() -> Int64 { value } }
    public let id: Id
}
public struct EngineMessage {
    public struct Id: Hashable { public let peerId: EnginePeer.Id; public let namespace: Int32; public let id: Int32 }
    public let id: Id
    public let text: String
    // This suite exercises caching; rich-page projection has its own production-model fixtures.
    public var rgTextContent: String { self.text }
    public let author: EnginePeer?
    public var adAttribute: Bool? { nil }
    public func effectivelyIncoming(_ id: EnginePeer.Id) -> Bool { self.author?.id != id }
    public func _asMessage() -> EngineRawMessage { EngineRawMessage(message: self) }
}
public struct EngineRawMessage {
    let message: EngineMessage
    public var id: EngineMessage.Id { self.message.id }
    public var rgTextContent: String { self.message.rgTextContent }
    public var author: EnginePeer? { self.message.author }
    public var adAttribute: Bool? { self.message.adAttribute }
    public func effectivelyIncoming(_ id: EnginePeer.Id) -> Bool { self.message.effectivelyIncoming(id) }
    public func withAppliedEphemeralReplacementMessage() -> EngineRawMessage { self }
}
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var messageFilterRules: [RGMessageFilterRule] = []
    var blockedPeerIds: Set<Int64> = []
    var groupHiddenSenders = RGGroupMemberSelection()
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
        func hidden(_ filter: RGContentFilterState, text: String) -> Bool {
            filter.shouldHide(RGContentFilterCandidate(id: id, text: text, authorId: peer, isIncoming: true))
        }
        settings.messageFilterRules = [disabled]
        expect(!hidden(state(), text: "blocked"), "Disabled rules must keep incoming messages visible")
        disabled.isEnabled = true
        settings.messageFilterRules = [disabled]
        let enabled = state()
        expect(hidden(enabled, text: "blocked"), "Enabling a rule must invalidate the cached visible result")
        expect(!hidden(enabled, text: "allowed"), "Same-length edits must invalidate the hidden result")
        expect(!enabled.shouldHide(RGContentFilterCandidate(id: id, text: "blocked", authorId: account, isIncoming: false)), "Sender and direction changes must invalidate the verdict for the same body")
        let sponsored = RGContentFilterCandidate(id: id, text: "blocked", authorId: peer, isIncoming: true, isSponsored: true)
        expect(enabled.shouldHide(sponsored), "A sponsored message must be tested against its own text")
        expect(!hidden(enabled, text: "allowed"), "A normal message must stay visible when a sponsored card with the same ID is hidden")
        expect(!enabled.shouldHide(RGContentFilterCandidate(id: id, text: "another ad", authorId: peer, isIncoming: true, isSponsored: true)), "Reused sponsored IDs must not share a verdict")
        settings.messageFilterRules.append(RGMessageFilterRule(pattern: "blocked", isException: true))
        let kept = state()
        expect(!hidden(kept, text: "blocked"), "Keep rules must invalidate cached hide verdicts")
        _ = hidden(enabled, text: "blocked")
        expect(!hidden(kept, text: "blocked"), "Late results from older rule generations must not poison the current cache")
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
        settings.messageFilterRules = []
        settings.groupHiddenSenders.set(accountId: 2, groupId: 1, senderId: 3, selected: true)
        let scoped = state()
        expect(!scoped.isEmpty, "A scoped sender alone must activate the history/list filter")
        expect(scoped.shouldHide(text: "", authorId: EnginePeer.Id(value: 3), peerId: peer, isIncoming: true), "Scoped hiding must cover media-only messages")
        expect(!scoped.shouldHide(text: "", authorId: EnginePeer.Id(value: 3), peerId: EnginePeer.Id(value: 4), isIncoming: true), "Other groups and private chats must stay visible")
        let otherAccount = RGContentFilterState(accountPeerId: EnginePeer.Id(value: 9))
        expect(!otherAccount.shouldHide(text: "", authorId: EnginePeer.Id(value: 3), peerId: peer, isIncoming: true), "Another account must not inherit a scoped block")
        expect(scoped.shouldHide(RGContentFilterCandidate(id: id, text: "", authorId: EnginePeer.Id(value: 3), isIncoming: true)), "Cache the scoped hidden result")
        expect(!otherAccount.shouldHide(RGContentFilterCandidate(id: id, text: "", authorId: EnginePeer.Id(value: 3), isIncoming: true)), "Identical message ids in another account must not share cached visibility")
        expect(scoped.shouldHide(RGContentFilterCandidate(id: id, text: "", authorId: EnginePeer.Id(value: 3), isIncoming: true)), "Repeated verdicts must remain account-scoped")
        settings.revealedPeerIds = [1]
        expect(!state().shouldHide(text: "", authorId: EnginePeer.Id(value: 3), peerId: peer, isIncoming: true), "Temporary reveal also recovers scoped hidden members")
        settings.revealedPeerIds = []
        settings.groupHiddenSenders = RGGroupMemberSelection()
        settings.messageFilterDisabledPeerIds = []
        settings.messageFilterRules = [disabled]
        let eviction = state()
        for index in 0..<8300 {
            let messageId = EngineMessage.Id(peerId: peer, namespace: 0, id: Int32(index))
            expect(eviction.shouldHide(RGContentFilterCandidate(id: messageId, text: "blocked", authorId: peer, isIncoming: true)), "Bounded cache eviction must retain matching behavior")
        }
        expect(hidden(eviction, text: "blocked"), "An evicted/edited message must be recomputed correctly")
        print("Content filter state checks passed: production verdict cache, enabled/keep generation changes, same-length edits, late passes, hidden senders, outgoing messages and 8300-entry eviction")
    }
}

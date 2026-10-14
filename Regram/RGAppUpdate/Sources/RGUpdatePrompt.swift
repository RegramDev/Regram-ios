// MARK: Regram — discovery and installation are different foreground prompts.
import Foundation

public struct RGUpdatePrompt: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case available, ready, failed(String)
        var identifier: String {
            switch self { case .available: return "available"; case .ready: return "ready"; case .failed: return "failed" }
        }
    }
    public let release: RGUpdateRelease
    public let kind: Kind
    public init(release: RGUpdateRelease, kind: Kind) { self.release = release; self.kind = kind }
}

public struct RGUpdatePromptPolicy {
    private var claimed = Set<String>()
    public init() {}
    public mutating func claim(_ prompt: RGUpdatePrompt, enabled: Bool, busy: Bool, currentRelease: RGUpdateRelease?, currentKind: RGUpdatePrompt.Kind?) -> Bool {
        guard enabled, !busy, currentKind == prompt.kind, currentRelease?.hasSameArtifact(as: prompt.release) == true else { return false }
        let key = prompt.release.version + ":" + String(prompt.release.build) + ":" + prompt.release.sha256 + ":" + prompt.kind.identifier
        return claimed.insert(key).inserted
    }
}

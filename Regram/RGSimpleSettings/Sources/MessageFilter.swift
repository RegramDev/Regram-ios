import Foundation

// MARK: Regram
// Message filter rules. A rule hides incoming messages whose text matches `pattern`, either as a
// plain case-insensitive substring or as a regular expression. `peerIds` narrows a rule to a set
// of conversations; an empty set means it applies everywhere.
//
// Rules are persisted as JSON in a single `UserDefaults` string so the shape can grow without
// adding a key per field (the `@UserDefault` wrapper only handles a fixed set of plist types).

public struct RGMessageFilterRule: Codable, Equatable {
    /// Stable identity, needed by the SwiftUI list and by edit-in-place.
    public var id: String
    public var pattern: String
    public var isRegex: Bool
    /// Conversations this rule is limited to. Empty means every conversation.
    public var peerIds: [Int64]

    public init(id: String = UUID().uuidString, pattern: String, isRegex: Bool = false, peerIds: [Int64] = []) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.peerIds = peerIds
    }

    public var appliesToAllChats: Bool {
        return self.peerIds.isEmpty
    }

    /// True when the rule is enabled for `peerId`. `nil` is treated as "unknown conversation",
    /// which only all-chat rules match.
    public func appliesTo(peerId: Int64?) -> Bool {
        if self.peerIds.isEmpty {
            return true
        }
        guard let peerId = peerId else {
            return false
        }
        return self.peerIds.contains(peerId)
    }

    /// A regex rule that does not compile is inert rather than matching everything, so a typo
    /// cannot silently hide a whole conversation.
    public var isValid: Bool {
        if self.pattern.isEmpty {
            return false
        }
        if self.isRegex {
            return RGMessageFilter.compiledRegex(for: self.pattern) != nil
        }
        return true
    }
}

public final class RGMessageFilter {
    /// `NSRegularExpression` construction is expensive relative to a per-message match, and the
    /// filter runs for every entry of every history view, so compiled patterns are memoised.
    /// Failed patterns are memoised too (as `nil`) to avoid re-parsing a broken rule each time.
    private static let regexCacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression?] = [:]

    public static func compiledRegex(for pattern: String) -> NSRegularExpression? {
        self.regexCacheLock.lock()
        defer { self.regexCacheLock.unlock() }
        if let cached = self.regexCache[pattern] {
            return cached
        }
        let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        self.regexCache[pattern] = compiled
        return compiled
    }

    public static func matches(rule: RGMessageFilterRule, text: String) -> Bool {
        if rule.pattern.isEmpty || text.isEmpty {
            return false
        }
        if rule.isRegex {
            guard let regex = self.compiledRegex(for: rule.pattern) else {
                return false
            }
            let range = NSRange(location: 0, length: (text as NSString).length)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return text.range(of: rule.pattern, options: [.caseInsensitive]) != nil
    }

    /// Whether any rule enabled for `peerId` matches `text`.
    public static func shouldHide(text: String, peerId: Int64?, rules: [RGMessageFilterRule]) -> Bool {
        if rules.isEmpty {
            return false
        }
        for rule in rules {
            if !rule.appliesTo(peerId: peerId) {
                continue
            }
            if self.matches(rule: rule, text: text) {
                return true
            }
        }
        return false
    }

    public static func encode(_ rules: [RGMessageFilterRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules), let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public static func decode(_ string: String) -> [RGMessageFilterRule] {
        guard let data = string.data(using: .utf8), let rules = try? JSONDecoder().decode([RGMessageFilterRule].self, from: data) else {
            return []
        }
        return rules
    }

    /// Name the rule export is written under. The JSON itself carries no marker, so the name is also
    /// how a shared export is recognised in a chat.
    public static let exportFileName = "regram-message-filter.json"

    /// Whether `fileName` is a rule export. A copy may pick up a suffix such as " 2" on the way.
    public static func isExportFileName(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        return lowercased.hasPrefix("regram-message-filter") && lowercased.hasSuffix(".json")
    }

    /// Adds `imported` to `existing` and returns the result with the number of rules added.
    ///
    /// Merged, not replaced: an import should never silently wipe rules the user still wants.
    /// Matching pattern + kind is treated as the same rule and skipped, and every imported rule gets
    /// a fresh id so it cannot collide with an existing row.
    public static func merging(_ imported: [RGMessageFilterRule], into existing: [RGMessageFilterRule]) -> (rules: [RGMessageFilterRule], addedCount: Int) {
        var merged = existing
        var addedCount = 0
        for rule in imported where !merged.contains(where: { $0.pattern == rule.pattern && $0.isRegex == rule.isRegex }) {
            merged.append(RGMessageFilterRule(pattern: rule.pattern, isRegex: rule.isRegex, peerIds: rule.peerIds))
            addedCount += 1
        }
        return (merged, addedCount)
    }
}

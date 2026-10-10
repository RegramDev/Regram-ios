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
    public var isEnabled: Bool
    /// A matching keep rule takes precedence over keyword/regex hide rules in the same chat.
    public var isException: Bool
    /// Conversations this rule is limited to. Empty means every conversation.
    public var peerIds: [Int64]

    public init(id: String = UUID().uuidString, pattern: String, isRegex: Bool = false, peerIds: [Int64] = [], isEnabled: Bool = true, isException: Bool = false) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.peerIds = peerIds
        self.isEnabled = isEnabled
        self.isException = isException
    }

    private enum CodingKeys: String, CodingKey { case id, pattern, isRegex, peerIds, isEnabled, isException }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try values.decode(String.self, forKey: .id)
        self.pattern = try values.decode(String.self, forKey: .pattern)
        self.isRegex = try values.decode(Bool.self, forKey: .isRegex)
        self.peerIds = try values.decode([Int64].self, forKey: .peerIds)
        self.isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isException = try values.decodeIfPresent(Bool.self, forKey: .isException) ?? false
    }

    public func hasSameDefinition(as other: RGMessageFilterRule) -> Bool {
        return self.pattern == other.pattern && self.isRegex == other.isRegex
            && self.isException == other.isException && Set(self.peerIds) == Set(other.peerIds)
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
    public enum MatchResult: Equatable { case matched, notMatched, disabled, invalidRegex, timedOut }
    /// Cooperative ICU progress callbacks stop expensive backtracking. A timed-out rule keeps the
    /// message visible; it must never silently turn into a match or block a history window forever.
    public static let regexTimeBudget: TimeInterval = 0.005
    /// `NSRegularExpression` construction is expensive relative to a per-message match, and the
    /// filter runs for every entry of every history view, so compiled patterns are memoised.
    /// Failed patterns are memoised too (as `nil`) to avoid re-parsing a broken rule each time.
    private static let regexCacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression?] = [:]
    private static var regexCacheOrder: [String] = []

    public static func compiledRegex(for pattern: String) -> NSRegularExpression? {
        self.regexCacheLock.lock()
        defer { self.regexCacheLock.unlock() }
        if let cached = self.regexCache[pattern] {
            return cached
        }
        let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        if self.regexCacheOrder.count == 4096 {
            self.regexCache.removeValue(forKey: self.regexCacheOrder.removeFirst())
        }
        self.regexCacheOrder.append(pattern)
        self.regexCache[pattern] = compiled
        return compiled
    }

    public static func matches(rule: RGMessageFilterRule, text: String) -> Bool {
        return self.matchResult(rule: rule, text: text) == .matched
    }

    public static func matchResult(rule: RGMessageFilterRule, text: String) -> MatchResult {
        return self.matchResult(rule: rule, text: text, string: text as NSString, needsSwiftMatching: self.needsSwiftMatching(text))
    }

    private static func needsSwiftMatching(_ text: String) -> Bool {
        // String and NSString differ for some non-ASCII case folds (e.g. ß and dotted İ).
        // Preserve the old behavior for these inputs; CJK, emoji and ASCII use the fast path.
        return text.unicodeScalars.contains { $0.value > 127 && $0.properties.isCased }
    }

    private static func matchResult(rule: RGMessageFilterRule, text: String, string: NSString, needsSwiftMatching: Bool) -> MatchResult {
        guard rule.isEnabled else { return .disabled }
        guard !rule.pattern.isEmpty, string.length != 0 else { return .notMatched }
        if rule.isRegex {
            guard let regex = self.compiledRegex(for: rule.pattern) else {
                return .invalidRegex
            }
            let deadline = ProcessInfo.processInfo.systemUptime + self.regexTimeBudget
            var result: MatchResult = .notMatched
            regex.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: string.length)) { match, _, stop in
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    result = .timedOut
                    stop.pointee = true
                } else if match != nil {
                    result = .matched
                    stop.pointee = true
                }
            }
            return result
        }
        // Keep Foundation's Unicode matching semantics without converting every result to Swift
        // String.Index. Bridge the message once for the whole rule pass, including no-hit scans.
        if needsSwiftMatching || self.needsSwiftMatching(rule.pattern) {
            return text.range(of: rule.pattern, options: .caseInsensitive) != nil ? .matched : .notMatched
        }
        return string.range(of: rule.pattern, options: .caseInsensitive).location != NSNotFound ? .matched : .notMatched
    }

    /// Whether any rule enabled for `peerId` matches `text`.
    public static func shouldHide(text: String, peerId: Int64?, rules: [RGMessageFilterRule]) -> Bool {
        if rules.isEmpty {
            return false
        }
        let string = text as NSString
        let needsSwiftMatching = self.needsSwiftMatching(text)
        for rule in rules where rule.isException && rule.isEnabled && rule.appliesTo(peerId: peerId) {
            let result = self.matchResult(rule: rule, text: text, string: string, needsSwiftMatching: needsSwiftMatching)
            if result == .matched || result == .timedOut { return false }
        }
        var timeoutCount = 0
        for rule in rules where !rule.isException && rule.isEnabled {
            if !rule.appliesTo(peerId: peerId) {
                continue
            }
            // Stop spending time on regex after repeated backtracking timeouts, while still
            // checking literal rules. Fast valid regex sets are not cut short by total scan time.
            if rule.isRegex && timeoutCount >= 4 { continue }
            let result = self.matchResult(rule: rule, text: text, string: string, needsSwiftMatching: needsSwiftMatching)
            if result == .matched {
                return true
            }
            if result == .timedOut { timeoutCount += 1 }
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
    /// Matching pattern, kind, action and conversation scope is treated as the same rule. Each import gets
    /// a fresh id so it cannot collide with an existing row.
    public static func merging(_ imported: [RGMessageFilterRule], into existing: [RGMessageFilterRule]) -> (rules: [RGMessageFilterRule], addedCount: Int) {
        var merged = existing
        var addedCount = 0
        for rule in imported where !merged.contains(where: { $0.hasSameDefinition(as: rule) }) {
            merged.append(RGMessageFilterRule(pattern: rule.pattern, isRegex: rule.isRegex, peerIds: rule.peerIds, isEnabled: rule.isEnabled, isException: rule.isException))
            addedCount += 1
        }
        return (merged, addedCount)
    }
}

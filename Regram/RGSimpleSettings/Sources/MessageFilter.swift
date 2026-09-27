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

    public init(id: String = UUID().uuidString, pattern: String, isRegex: Bool = true, peerIds: [Int64] = []) {
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
        if self.pattern.isEmpty || self.pattern.utf16.count > RGMessageFilter.maximumPatternLength {
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
    private struct CachedRegex {
        let value: NSRegularExpression?
    }
    private static var regexCache: [String: CachedRegex] = [:]
    private static var regexOrder: [String] = []
    private static var nextRegexEviction = 0
    private static let regexCacheLimit = 128
    private static var slowPatterns = Set<String>()
    public static func isPaused(_ pattern: String) -> Bool {
        self.regexCacheLock.lock(); defer { self.regexCacheLock.unlock() }
        return self.slowPatterns.contains(pattern)
    }
    public static func resetPausedPatterns() {
        self.regexCacheLock.lock(); self.slowPatterns.removeAll(); self.regexCacheLock.unlock()
    }
    public static let maximumImportBytes = 2 * 1024 * 1024
    public static let maximumRuleCount = 4096
    public static let maximumPatternLength = 4096
    /// A single message gets one small regex budget. Without a per-message budget, a large rule
    /// set could spend the timeout once per rule and turn a background rebuild into minutes of CPU.
    static let maximumMatchDuration: TimeInterval = 0.003

    public enum ImportError: Error {
        case fileTooLarge
        case tooManyRules
        case invalidRules
        case cancelled
    }

    public static func compiledRegex(for pattern: String) -> NSRegularExpression? {
        guard pattern.utf16.count <= self.maximumPatternLength else { return nil }
        self.regexCacheLock.lock()
        if let cached = self.regexCache[pattern] {
            self.regexCacheLock.unlock()
            return cached.value
        }
        self.regexCacheLock.unlock()
        let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        self.regexCacheLock.lock()
        defer { self.regexCacheLock.unlock() }
        if self.regexCache[pattern] == nil {
            if self.regexOrder.count == self.regexCacheLimit {
                self.regexCache.removeValue(forKey: self.regexOrder[self.nextRegexEviction])
                self.regexOrder[self.nextRegexEviction] = pattern
                self.nextRegexEviction = (self.nextRegexEviction + 1) % self.regexCacheLimit
            } else {
                self.regexOrder.append(pattern)
            }
            self.regexCache[pattern] = CachedRegex(value: compiled)
        }
        return compiled
    }

    /// ICU periodically reports progress even during backtracking. Stop at the first match, the
    /// deadline, or cancellation; a timed-out rule leaves the message visible.
    public static func boundedMatch(_ regex: NSRegularExpression, text: String, range: NSRange, deadline: TimeInterval, isCancelled: () -> Bool = { false }) -> Bool {
        guard !self.isPaused(regex.pattern), !isCancelled(), ProcessInfo.processInfo.systemUptime < deadline else {
            return false
        }
        var matched = false
        var exceeded = false
        regex.enumerateMatches(in: text, options: [.reportProgress], range: range) { result, _, stop in
            if isCancelled() {
                stop.pointee = true
            } else if ProcessInfo.processInfo.systemUptime >= deadline {
                exceeded = true
                stop.pointee = true
            } else if result != nil {
                matched = true
                stop.pointee = true
            }
        }
        if exceeded {
            self.regexCacheLock.lock()
            let inserted = self.slowPatterns.insert(regex.pattern).inserted
            self.regexCacheLock.unlock()
            if inserted { DispatchQueue.main.async { RGSimpleSettings.shared.invalidateSlowRuleResults() } }
        }
        return matched
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
            return self.boundedMatch(regex, text: text, range: range, deadline: ProcessInfo.processInfo.systemUptime + self.maximumMatchDuration)
        }
        return text.range(of: rule.pattern, options: [.caseInsensitive]) != nil
    }

    /// Whether any rule enabled for `peerId` matches `text`.
    public static func shouldHide(text: String, peerId: Int64?, rules: [RGMessageFilterRule]) -> Bool {
        for rule in rules where rule.appliesTo(peerId: peerId) {
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

    public static func readImport(at url: URL) throws -> [RGMessageFilterRule] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        // `read(upToCount:)` is unavailable on the older iOS versions this target still supports.
        // Reading one byte past the limit keeps the same bounded-size check without loading an
        // untrusted export into memory.
        let data = handle.readData(ofLength: self.maximumImportBytes + 1)
        guard data.count <= self.maximumImportBytes else { throw ImportError.fileTooLarge }
        guard let rules = try? JSONDecoder().decode([RGMessageFilterRule].self, from: data), !rules.isEmpty else {
            throw ImportError.invalidRules
        }
        guard rules.count <= self.maximumRuleCount else { throw ImportError.tooManyRules }
        guard rules.allSatisfy({ $0.pattern.count <= self.maximumPatternLength && $0.isValid }) else {
            throw ImportError.invalidRules
        }
        return rules
    }

    private struct RuleKey: Hashable {
        let pattern: String
        let isRegex: Bool
        let peerIds: [Int64]

        init(_ rule: RGMessageFilterRule) {
            self.pattern = rule.pattern
            self.isRegex = rule.isRegex
            self.peerIds = Array(Set(rule.peerIds)).sorted()
        }
    }

    public static func equivalent(_ lhs: RGMessageFilterRule, _ rhs: RGMessageFilterRule) -> Bool {
        return RuleKey(lhs) == RuleKey(rhs)
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
    /// Scope is part of identity. Every imported rule gets a fresh id to avoid row collisions.
    public static func merging(_ imported: [RGMessageFilterRule], into existing: [RGMessageFilterRule]) -> (rules: [RGMessageFilterRule], addedCount: Int) {
        var merged = existing
        var keys = Set(existing.map(RuleKey.init))
        var addedCount = 0
        for rule in imported where keys.insert(RuleKey(rule)).inserted {
            merged.append(RGMessageFilterRule(pattern: rule.pattern, isRegex: rule.isRegex, peerIds: Array(Set(rule.peerIds)).sorted()))
            addedCount += 1
        }
        return (merged, addedCount)
    }
}

/// Immutable ruleset shared by one filtering pass. Regular expressions and chat scopes are
/// prepared once when settings change; matching a message does not decode JSON or take a lock.
public final class RGMessageFilterMatcher {
    private struct Entry {
        let pattern: String
        let regex: NSRegularExpression?
        let scopedPeerIds: Set<Int64>?
    }

    public let rules: [RGMessageFilterRule]
    private let preparationLock = NSLock()
    private var preparedEntries: [Entry]?
    public let isEmpty: Bool

    public init(rules: [RGMessageFilterRule]) {
        self.rules = rules
        self.isEmpty = rules.allSatisfy { $0.pattern.isEmpty }
    }

    private func entries(isCancelled: () -> Bool) -> [Entry]? {
        self.preparationLock.lock()
        let cached = self.preparedEntries
        self.preparationLock.unlock()
        if let cached { return cached }
        var result: [Entry] = []
        for rule in self.rules {
            if isCancelled() { return nil }
            if rule.pattern.isEmpty { continue }
            let regex = rule.isRegex ? RGMessageFilter.compiledRegex(for: rule.pattern) : nil
            if rule.isRegex && regex == nil { continue }
            result.append(Entry(pattern: rule.pattern, regex: regex, scopedPeerIds: rule.peerIds.isEmpty ? nil : Set(rule.peerIds)))
        }
        self.preparationLock.lock()
        self.preparedEntries = result
        self.preparationLock.unlock()
        return result
    }

    public func shouldHide(text: String, peerId: Int64?, isCancelled: () -> Bool = { false }) -> Bool {
        guard !text.isEmpty, let entries = self.entries(isCancelled: isCancelled) else {
            return false
        }
        var utf16Range: NSRange?
        // Literal rules are bounded by the system's string search and should not lose their turn
        // because an earlier regex consumed the regex budget.
        for entry in entries {
            if isCancelled() { return false }
            if let scopedPeerIds = entry.scopedPeerIds {
                guard let peerId, scopedPeerIds.contains(peerId) else {
                    continue
                }
            }
            if entry.regex == nil, text.range(of: entry.pattern, options: [.caseInsensitive]) != nil {
                return true
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + RGMessageFilter.maximumMatchDuration
        for entry in entries {
            if isCancelled() { return false }
            guard let scopedPeerIds = entry.scopedPeerIds else {
                // Continue below for an all-chat regex.
                if let regex = entry.regex {
                    let range = utf16Range ?? NSRange(location: 0, length: (text as NSString).length)
                    utf16Range = range
                    if RGMessageFilter.boundedMatch(regex, text: text, range: range, deadline: deadline, isCancelled: isCancelled) { return true }
                }
                continue
            }
            guard let peerId, scopedPeerIds.contains(peerId), let regex = entry.regex else {
                continue
            }
            let range = utf16Range ?? NSRange(location: 0, length: (text as NSString).length)
            utf16Range = range
            if RGMessageFilter.boundedMatch(regex, text: text, range: range, deadline: deadline, isCancelled: isCancelled) { return true }
        }
        return false
    }
}

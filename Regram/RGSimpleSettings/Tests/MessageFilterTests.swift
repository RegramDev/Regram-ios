import Foundation

@main private enum MessageFilterTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() {
        let legacy = "[{\"id\":\"old\",\"pattern\":\"spam\",\"isRegex\":false,\"peerIds\":[]}]"
        let old = RGMessageFilter.decode(legacy)
        expect(old.count == 1 && old[0].isEnabled && !old[0].isException, "Existing rules must remain active hide rules")
        let hide = RGMessageFilterRule(pattern: "广告", peerIds: [1])
        let keep = RGMessageFilterRule(pattern: "已审核", peerIds: [1], isException: true)
        expect(RGMessageFilter.shouldHide(text: "广告", peerId: 1, rules: [hide]), "Chat-scoped hide must apply")
        expect(!RGMessageFilter.shouldHide(text: "广告", peerId: 2, rules: [hide]), "Other chats must be unaffected")
        expect(!RGMessageFilter.shouldHide(text: "广告 已审核", peerId: 1, rules: [hide, keep]), "Keep rules must override hides regardless of ordering")
        var disabled = keep; disabled.isEnabled = false
        expect(RGMessageFilter.shouldHide(text: "广告 已审核", peerId: 1, rules: [disabled, hide]), "Disabled keep must not override hide")
        expect(RGMessageFilter.matchResult(rule: disabled, text: "已审核") == .disabled, "Disabled rule diagnostic")
        expect(RGMessageFilter.decode(RGMessageFilter.encode([disabled, keep])) == [disabled, keep], "New fields must survive export/import")
        let scoped = RGMessageFilterRule(pattern: "广告", peerIds: [2])
        let merged = RGMessageFilter.merging([scoped, hide, keep, disabled], into: [hide])
        expect(merged.addedCount == 2 && merged.rules.count == 3, "Import must preserve different chat scopes and keep actions while deduplicating identical definitions")
        let reordered = RGMessageFilterRule(pattern: "广告", peerIds: [2, 1, 1])
        expect(reordered.hasSameDefinition(as: RGMessageFilterRule(pattern: "广告", peerIds: [1, 2])), "Scope order and duplicates are not distinct definitions")
        expect(Set(merged.rules.map { $0.id }).count == merged.rules.count, "Imported IDs must be fresh")
        let atoms = ["", "广告", "廣告", "a", "A", "ß", "ss", "İ", "i", "ı", "é", "e\u{301}", "Σ", "ς", "σ", "👩🏽‍💻", "🐈", "Ａ", "a\n", "\u{F900}", "豈", "가", "가"]
        for left in atoms { for right in atoms {
            let text = "前缀" + left + right + " suffix"
            for pattern in atoms where !pattern.isEmpty {
                let expected = text.range(of: pattern, options: .caseInsensitive) != nil
                expect(RGMessageFilter.matches(rule: RGMessageFilterRule(pattern: pattern), text: text) == expected, "Unicode/case/canonical matching regression: \(pattern) in \(text)")
            }
        } }
        expect(RGMessageFilter.matchResult(rule: RGMessageFilterRule(pattern: "[", isRegex: true), text: "hello") == .invalidRegex, "Malformed regex must be inert")
        expect(RGMessageFilter.matches(rule: RGMessageFilterRule(pattern: "^(spam|广告)\\d+$", isRegex: true), text: "SPAM42"), "Normal case-insensitive regex must still work")
        let pathological = RGMessageFilterRule(pattern: "^(a+)+$", isRegex: true)
        let input = String(repeating: "a", count: 40) + "!"
        let begin = ProcessInfo.processInfo.systemUptime
        expect(RGMessageFilter.matchResult(rule: pathological, text: input) == .timedOut, "Backtracking must be reported and cancelled")
        expect(ProcessInfo.processInfo.systemUptime - begin < 0.5, "Regex progress cancellation must prevent multi-second stalls")
        let passBegin = ProcessInfo.processInfo.systemUptime
        expect(!RGMessageFilter.shouldHide(text: input, peerId: 1, rules: (0..<100).map { _ in pathological }), "Timed-out rules must keep messages visible")
        expect(ProcessInfo.processInfo.systemUptime - passBegin < 0.5, "Repeated backtracking timeouts must stop further regex work")
        let normalRules = (0..<1000).map { RGMessageFilterRule(pattern: "^sample\($0)$", isRegex: true) }
        for rule in normalRules { _ = RGMessageFilter.compiledRegex(for: rule.pattern) }
        expect(RGMessageFilter.shouldHide(text: "sample999", peerId: 1, rules: normalRules), "A large set of safe cached regex rules must still reach its last rule")
        for i in 0..<4200 { _ = RGMessageFilter.compiledRegex(for: "sample\(i)") }
        expect(RGMessageFilter.matches(rule: RGMessageFilterRule(pattern: "^spam$", isRegex: true), text: "SPAM"), "Evicted patterns must be recompiled correctly")
        print("Message filter checks passed: legacy/new storage, scopes, keep precedence, disabled rules, import merging, 11638 Unicode comparisons, normal/invalid regex and bounded backtracking")
    }
}

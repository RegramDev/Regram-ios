import Foundation

/// Shared, versioned policy bundled with every app. No model-generated labels become training truth.
/// New public rules require reviewed fixtures; private corrections remain account/source scoped.
public enum RGAdPolicy {
    public static let revision = 1

    public static func rules(for input: RGAdInput, samples: [RGAdSample], sourceGroup: String) -> [RGAdRule] {
        let source = input.text as NSString
        let lines = RGAdFilter.paragraphRanges(input.text)
        var rules: [RGAdRule] = []
        for line in lines {
            let text = source.substring(with: line.nsRange).trimmingCharacters(in: .whitespacesAndNewlines)
            // Commentary, warnings and reporting are not promotional copy.
            if text.range(of: "警惕|谨防|诈骗|騙|骗局|报道|報道|曝光|反诈|不要|切勿|案例|举报|舉報|新闻|新聞", options: .regularExpression) != nil { continue }
            let hasDestination = input.entities.contains { [.link, .mention].contains($0.kind) && line.contains($0.range) }
            let combined = text.range(of: "0\\s*充值.{0,24}(免费体验|免費體驗).{0,24}(中奖可提现|中獎可提現)|实力飞投.{0,24}超高限红.{0,24}大额无忧|實力飛投.{0,24}超高限紅.{0,24}大額無憂", options: .regularExpression) != nil
            let signup = text.range(of: "新人注册送\\s*[0-9]+\\s*[uU]|新人註冊送\\s*[0-9]+\\s*[uU]", options: .regularExpression) != nil && text.range(of: "8g.com|8G.COM|博彩|盘口|盤口", options: .regularExpression) != nil
            if hasDestination && (combined || signup), text.count >= 12 { rules.append(RGAdRule(text, scope: .paragraph)) }
        }
        // Reuse only exact reviewed snippets in the same channel. Short keywords and raw domains
        // are never learned as broad deletion rules. Normal/uncertain examples veto conflicts.
        let local = samples.filter { $0.sourceGroup == sourceGroup && $0.reviewedAt != nil }
        for sample in local {
            for span in sample.spans where span.label == .ad {
                let snippet = (sample.input.text as NSString).substring(with: span.range.nsRange)
                guard snippet.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12, snippet.utf16.count <= 4096 else { continue }
                let veto = local.contains { other in
                    let range = (other.input.text as NSString).range(of: snippet)
                    guard range.location != NSNotFound else { return false }
                    return !other.spans.contains { $0.label == .ad && $0.range.contains(RGAdRange(range.location, NSMaxRange(range))) }
                }
                if !veto { rules.append(RGAdRule(snippet, scope: .match)) }
            }
        }
        var seen = Set<String>()
        return Array(rules.filter { seen.insert($0.kind.rawValue + $0.scope.rawValue + $0.pattern).inserted }.prefix(128))
    }

    public static func project(_ input: RGAdInput, samples: [RGAdSample] = [], sourceGroup: String = "") throws -> RGAdProjection {
        // Exact reviewed snapshots override the automatic policy, including a fully normal example.
        let sanitized = RGAdInput(text: input.text, entities: input.entities, buttons: input.buttons, hasMedia: input.hasMedia, previewTarget: input.previewTarget)
        if let sample = samples.first(where: { $0.sourceGroup == sourceGroup && $0.input == sanitized && $0.reviewedAt != nil }) {
            return try RGAdFilter.project(input, confirmedRanges: sample.spans.filter { $0.label == .ad }.map(\.range), confirmedButtonIds: Set(sample.buttonLabels.filter { $0.value == .ad }.keys), inferButtons: false)
        }
        let local = samples.filter { $0.sourceGroup == sourceGroup && $0.reviewedAt != nil }
        let removedButtons = input.buttons.flatMap { $0 }.filter { button in
            guard let target = RGAdFilter.normalizedTarget(button.target) else { return false }
            let matches = local.flatMap { sample in sample.input.buttons.flatMap { $0 }.compactMap { known -> RGAdLabel? in
                known.title == button.title && RGAdFilter.normalizedTarget(known.target) == target ? sample.buttonLabels[known.id] : nil
            } }
            if matches.contains(where: { $0 != .ad }) { return false }
            return matches.contains(.ad) || ["广告合作招商", "廣告合作招商"].contains(button.title.trimmingCharacters(in: .whitespacesAndNewlines))
        }.map(\.id)
        return try RGAdFilter.project(input, rules: rules(for: input, samples: samples, sourceGroup: sourceGroup), confirmedButtonIds: Set(removedButtons))
    }
}

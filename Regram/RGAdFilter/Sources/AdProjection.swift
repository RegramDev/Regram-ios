import Foundation

/// Pure, account-free projection. The source message/database are never modified.
public enum RGAdFilter {
    public static func project(_ input: RGAdInput, rules: [RGAdRule] = [], predictions: [RGAdPrediction] = [], threshold: Double = 0.98, suggestedRanges: [RGAdRange] = [], confirmedRanges: [RGAdRange] = [], confirmedButtonIds: Set<String> = [], inferButtons: Bool = true) throws -> RGAdProjection {
        guard input.text.utf16.count <= 65_536, input.entities.count <= 2048, rules.count <= 128,
              predictions.count <= 1024, suggestedRanges.count <= 1024, confirmedRanges.count <= 1024, confirmedButtonIds.count <= 128, input.buttons.count <= 128 else { throw RGAdFilterError.invalidInput }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        let boundaries = rgAdBoundaries(input.text)
        let allButtons = input.buttons.flatMap { $0 }
        guard allButtons.count <= 128, allButtons.allSatisfy({ $0.title.utf16.count <= 1024 }), threshold.isFinite, (0...1).contains(threshold),
              input.entities.allSatisfy({ rgAdValid($0.range, boundaries: boundaries) }),
              Set(allButtons.map(\.id)).count == allButtons.count else { throw RGAdFilterError.invalidInput }
        let source = input.text as NSString
        let paragraphs = paragraphRanges(input.text)
        var ranges: [RGAdRange] = suggestedRanges + confirmedRanges
        var removedButtons = confirmedButtonIds
        let activeRules = rules.filter { !$0.pattern.isEmpty && ($0.peerId == nil || $0.peerId == input.peerId) }
        for rule in activeRules {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
            let matches: [RGAdRange]
            if rule.kind == .target {
                matches = input.entities.compactMap { entity in
                    guard let target = entityTarget(entity, text: source), target == normalizedTarget(rule.pattern) else { return nil }
                    return entity.range
                }
            } else {
                matches = matchRanges(rule, text: input.text)
            }
            for match in matches {
                if rule.scope == .paragraph {
                    // Newlines define hard boundaries. A rule cannot erase unrelated later paragraphs.
                    ranges += paragraphs.filter { $0.intersects(match) }
                } else { ranges.append(match) }
            }
            for button in allButtons {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
                let matched: Bool
                if rule.kind == .target {
                    matched = normalizedTarget(button.target) != nil && normalizedTarget(button.target) == normalizedTarget(rule.pattern)
                } else { matched = !matchRanges(rule, text: button.title).isEmpty }
                if matched { removedButtons.insert(button.id) }
            }
        }
        // The prototype only acts on complete model-selected paragraphs. Token fragments are
        // useful diagnostics, but stripping a few confident characters can change the meaning.
        ranges += predictions.filter { prediction in
            guard prediction.confidence.isFinite, prediction.confidence >= threshold, prediction.confidence <= 1,
                  rgAdValid(prediction.range, boundaries: boundaries),
                  paragraphs.contains(where: { $0.lower == prediction.range.lower }),
                  paragraphs.contains(where: { $0.upper == prediction.range.upper }) else { return false }
            return source.substring(with: prediction.range.nsRange).trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
        }.map(\.range)
        // Reject partial graphemes, protected quotations/code, and cuts through atomic entities.
        ranges = ranges.filter { range in
            guard rgAdValid(range, boundaries: boundaries) else { return false }
            return !input.entities.contains { entity in
                guard entity.range.intersects(range) else { return false }
                switch entity.kind {
                case .code, .quote: return !confirmedRanges.contains(where: { $0.contains(range) })
                case .link, .mention, .customEmoji: return !range.contains(entity.range)
                case .format: return false
                }
            }
        }
        ranges = merge(ranges)
        // Only remove separator lines adjacent to a confirmed removed block. Keep other content.
        for (index, paragraph) in paragraphs.enumerated() where isSeparator(source.substring(with: paragraph.nsRange)) {
            if index + 1 < paragraphs.count && ranges.contains(where: { $0.contains(paragraphs[index + 1]) }) {
                if !input.entities.contains(where: { $0.range.intersects(paragraph) }) { ranges.append(paragraph) }
            }
        }
        ranges = merge(ranges)
        let remaining = complement(ranges, length: source.length)
        var text = ""
        var mappedEntities: [RGAdEntity] = []
        var offset = 0
        for kept in remaining {
            text += source.substring(with: kept.nsRange)
            for entity in input.entities where entity.range.intersects(kept) {
                let clipped = RGAdRange(max(entity.range.lower, kept.lower), min(entity.range.upper, kept.upper))
                mappedEntities.append(RGAdEntity(range: RGAdRange(offset + clipped.lower - kept.lower, offset + clipped.upper - kept.lower), kind: entity.kind, value: entity.value))
            }
            offset += kept.upper - kept.lower
        }
        var removedTargets = Set<String>()
        var keptTargets = Set<String>()
        for entity in input.entities {
            guard let target = entityTarget(entity, text: source) else { continue }
            if ranges.contains(where: { $0.contains(entity.range) }) { removedTargets.insert(target) }
            else { keptTargets.insert(target) }
        }
        // A normal surviving link to the same destination prevents inferred button removal.
        removedTargets.subtract(keptTargets)
        for button in allButtons {
            if inferButtons, let target = normalizedTarget(button.target), removedTargets.contains(target) { removedButtons.insert(button.id) }
        }
        let buttons = input.buttons.map { $0.filter { !removedButtons.contains($0.id) } }.filter { !$0.isEmpty }
        let hidePreview = normalizedTarget(input.previewTarget).map { removedTargets.contains($0) } ?? false
        let changed = !ranges.isEmpty || !removedButtons.isEmpty || hidePreview
        let hide = changed && !input.hasMedia && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && buttons.isEmpty
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
        return RGAdProjection(disposition: hide ? .hide : (changed ? .trim : .keep), text: text, entities: mappedEntities, buttons: buttons,
                              removedRanges: ranges, removedButtonIds: allButtons.map(\.id).filter { removedButtons.contains($0) }, hideLinkPreview: hidePreview)
    }

    private static func matchRanges(_ rule: RGAdRule, text: String) -> [RGAdRange] {
        let source = text as NSString
        guard source.length <= 65_536, rule.pattern.utf16.count <= 4096 else { return [] }
        if rule.kind == .regex {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) else { return [] }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.005
            var result: [RGAdRange] = []
            var timedOut = false
            regex.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: source.length)) { match, _, stop in
                if ProcessInfo.processInfo.systemUptime >= deadline || result.count >= 1024 {
                    timedOut = true; stop.pointee = true
                } else if let range = match?.range, range.length > 0 { result.append(RGAdRange(range.location, NSMaxRange(range))) }
            }
            return timedOut ? [] : result
        }
        var result: [RGAdRange] = []
        var start = 0
        while start < source.length && result.count < 1024 {
            let range = source.range(of: rule.pattern, options: .caseInsensitive, range: NSRange(location: start, length: source.length - start))
            if range.location == NSNotFound || range.length == 0 { break }
            result.append(RGAdRange(range.location, NSMaxRange(range))); start = NSMaxRange(range)
        }
        return result
    }

    static func paragraphRanges(_ text: String) -> [RGAdRange] {
        var result: [RGAdRange] = []
        var lower = 0
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            if character.isNewline { result.append(RGAdRange(lower, offset)); lower = offset }
        }
        if lower < offset { result.append(RGAdRange(lower, offset)) }
        return result
    }

    private static func isSeparator(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 3 && value.unicodeScalars.allSatisfy { "-=─━═_—".unicodeScalars.contains($0) }
    }

    private static func entityTarget(_ entity: RGAdEntity, text: NSString) -> String? {
        guard entity.kind == .link || entity.kind == .mention else { return nil }
        return normalizedTarget(entity.value ?? text.substring(with: entity.range.nsRange))
    }

    /// Exact resource identity, never a whole-domain blacklist or a network redirect lookup.
    public static func normalizedTarget(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        func username(_ value: String) -> String? {
            guard (1...32).contains(value.count), value.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "_" }) else { return nil }
            return "telegram-user:" + value.lowercased()
        }
        if value.hasPrefix("@") { return username(String(value.dropFirst())) }
        guard var url = URLComponents(string: value), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return nil }
        if ["t.me", "telegram.me"].contains(host), url.port == nil, url.query == nil, url.fragment == nil {
            let components = url.path.split(separator: "/")
            if components.count == 1, let identity = username(String(components[0])) { return identity }
        }
        url.scheme = scheme; url.host = host
        if (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80) { url.port = nil }
        if url.path.isEmpty { url.path = "/" }
        return url.string
    }

    private static func merge(_ input: [RGAdRange]) -> [RGAdRange] {
        var result: [RGAdRange] = []
        for range in input.sorted(by: { $0.lower == $1.lower ? $0.upper < $1.upper : $0.lower < $1.lower }) {
            if let last = result.last, last.upper >= range.lower { result[result.count - 1] = RGAdRange(last.lower, max(last.upper, range.upper)) }
            else { result.append(range) }
        }
        return result
    }

    private static func complement(_ removed: [RGAdRange], length: Int) -> [RGAdRange] {
        var result: [RGAdRange] = []; var offset = 0
        for range in removed { if offset < range.lower { result.append(RGAdRange(offset, range.lower)) }; offset = range.upper }
        if offset < length { result.append(RGAdRange(offset, length)) }
        return result
    }
}

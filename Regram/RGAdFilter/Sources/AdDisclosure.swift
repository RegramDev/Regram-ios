import Foundation

/// Author-supplied disclosure tags describe a message or a delimited section.
/// They are independent of model availability and never act as substring keywords.
enum RGAdDisclosure {
    // Explicit commercial declarations only. Broad topics such as recommendations,
    // benefits, collaboration or ordinary "sponsor" discussions are not declarations.
    static let tags = [
        "推广", "推廣", "广告", "廣告", "商业推广", "商業推廣", "付费推广", "付費推廣",
        "商业合作", "商業合作", "付费合作", "付費合作", "业配", "業配", "广宣", "廣宣",
        "ad", "ads", "advert", "adverts", "advertisement", "advertisements", "advertising",
        "sponsored", "sponsoredpost", "sponsored_post", "sponsoredcontent", "sponsored_content",
        "paidpromotion", "paid_promotion", "paidpartnership", "paid_partnership", "promo", "promotion", "promoted"
    ]
    private static let disclosure = try! NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}\\p{M}_/#＃])(?:#|＃)(?:" + tags.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")(?![\\p{L}\\p{N}\\p{M}_])",
        options: .caseInsensitive
    )
    private static let hashtag = try! NSRegularExpression(pattern: "[#＃][\\p{L}\\p{N}\\p{M}_]+")
    private static let url = try! NSRegularExpression(pattern: "(?:https?://|tg://|www\\.)[^\\s]+", options: .caseInsensitive)

    private static func onlyTagsAndDecoration(_ text: String) -> Bool {
        let stripped = hashtag.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")
        // Quoted tag names are discussion/examples, not the author's disclosure.
        return !stripped.contains(where: { "\"'`“”‘’「」『』«»".contains($0) })
            && !stripped.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
    }

    /// Telegram authors use monospace for copyable redemption instructions as
    /// well as code. Admit short, single-line natural-language labels only on a
    /// whole card explicitly disclosed by its author; programming syntax stays.
    static func isTextLabel(_ entity: RGAdEntity, source: NSString) -> Bool {
        guard entity.kind == .code, entity.range.lower >= 0, entity.range.upper <= source.length,
              (1...128).contains(entity.range.upper - entity.range.lower) else { return false }
        let value = source.substring(with: entity.range.nsRange)
        return !value.contains(where: { $0.isNewline || "{}[]=<>\\();".contains($0) })
            && value.unicodeScalars.filter({ (0x3400...0x9fff).contains($0.value) }).count >= 4
    }

    static func ranges(_ input: RGAdInput) -> [RGAdRange] {
        let source = input.text as NSString
        guard source.length <= 65_536, input.entities.count <= 2048 else { return [] }
        let matches = disclosure.matches(in: input.text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty, matches.count <= 128 else { return [] }
        let destinations = url.matches(in: input.text, range: NSRange(location: 0, length: source.length)).map { RGAdRange($0.range.location, NSMaxRange($0.range)) }
        let boundaries = rgAdBoundaries(input.text)
        let lines = RGAdFilter.paragraphRanges(input.text)
        let blocks = RGAdFilter.contextRanges(input.text)
        let sentences = RGAdFilter.semanticRanges(input.text, entities: input.entities)
        func text(_ range: RGAdRange) -> String { source.substring(with: range.nsRange) }
        func empty(_ range: RGAdRange) -> Bool { text(range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func normalTags(_ range: RGAdRange) -> Bool {
            let value = text(range)
            return onlyTagsAndDecoration(value)
                && hashtag.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) != nil
                && disclosure.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) == nil
        }
        var result: [RGAdRange] = []
        for match in matches {
            let marker = RGAdRange(match.range.location, NSMaxRange(match.range))
            guard rgAdValid(marker, boundaries: boundaries),
                  !destinations.contains(where: { $0.intersects(marker) }),
                  !input.entities.contains(where: { $0.kind != .format && $0.range.intersects(marker) }),
                  let index = lines.firstIndex(where: { $0.contains(marker) }) else { continue }
            let line = lines[index]
            let sentence = sentences.first(where: { $0.contains(marker) }) ?? line
            let inlineHead = sentence.lower > line.lower
            let prefix = text(RGAdRange(max(line.lower, sentence.lower), marker.lower))
            let suffix = text(RGAdRange(marker.upper, min(line.upper, sentence.upper)))
            let labelOnly = onlyTagsAndDecoration(text(line))
            // A tag embedded in prose is only actionable at the start/end of an
            // advertising sentence, never a quoted name or a word being discussed.
            guard labelOnly || onlyTagsAndDecoration(prefix) || onlyTagsAndDecoration(suffix) else { continue }
            if prefix.last.map({ "\"'`“‘「『«".contains($0) }) == true
                || suffix.first.map({ "\"'`”’」』»".contains($0) }) == true { continue }

            var lower = 0, upper = source.length
            if index > 0 {
                for previous in lines[..<index].reversed() {
                    if RGAdFilter.isSeparator(text(previous)) || normalTags(previous) { lower = previous.upper; break }
                }
            }
            if index + 1 < lines.count {
                for next in lines[(index + 1)...] {
                    if RGAdFilter.isSeparator(text(next)) { upper = next.lower; break }
                    if normalTags(next) { upper = next.lower; break }
                }
            }
            // Standalone metadata at the head/tail describes the containing
            // section. An attached inline tag describes its own paragraph/sentence.
            let before = RGAdRange(lower, line.lower), after = RGAdRange(line.upper, upper)
            // A category row embedded inside an article (for example, an ad-blocking
            // app tagged with SMS/phone/ad/blocking) is not a section disclosure.
            if labelOnly && !empty(before) && !empty(after) {
                guard hashtag.numberOfMatches(in: text(line), range: NSRange(location: 0, length: line.upper - line.lower)) == 1 else { continue }
                // A standalone declaration between normal sections introduces the
                // adjacent paragraph. Do not consume later unrelated paragraphs.
                let nextBody = blocks.first(where: { $0.contains(marker) && !empty(RGAdRange(line.upper, $0.upper)) })
                    ?? blocks.first(where: { $0.lower >= line.upper && !empty($0) })
                guard let nextBody else { continue }
                lower = line.lower; upper = min(upper, nextBody.upper)
            } else if labelOnly && (empty(before) || empty(after)) {
                // Keep the whole hard-delimited section, including feature lists,
                // navigation, contacts, coupon labels and the disclosure itself.
            } else if onlyTagsAndDecoration(prefix),
                      let block = blocks.first(where: { $0.contains(marker) }) {
                lower = max(lower, inlineHead ? sentence.lower : line.lower)
                upper = min(upper, inlineHead ? sentence.upper : block.upper)
            } else if onlyTagsAndDecoration(suffix) {
                lower = max(lower, sentence.lower); upper = min(upper, sentence.upper)
            } else { continue }
            let range = RGAdRange(lower, upper)
            guard rgAdValid(range, boundaries: boundaries),
                  !input.entities.contains(where: { entity in
                      guard entity.range.intersects(range) else { return false }
                      if entity.kind == .code {
                          guard entity.range.lower >= 0, entity.range.upper <= source.length else { return true }
                          return !RGAdFilter.isInlineCodeLabel(entity, source: source)
                              && !(range == RGAdRange(0, source.length) && isTextLabel(entity, source: source))
                      }
                      if [.link, .mention, .customEmoji].contains(entity.kind) { return !range.contains(entity.range) }
                      return false
                  }) else { continue }
            if !result.contains(range) { result.append(range) }
        }
        return result
    }
}

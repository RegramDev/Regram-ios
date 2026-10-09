import Foundation

/// Protect link labels and literal addresses from plain-text translation backends. Native entity
/// types stay with the caller; indices identify them without coupling this module to TelegramCore.
public struct RGTranslationLinkPlan {
    public struct ProtectedRange {
        public let range: NSRange
        public let id: Int
        public init(range: NSRange, id: Int) { self.range = range; self.id = id }
    }
    public struct Segment {
        public let text: String
        public let id: Int?
    }
    public let segments: [Segment]

    public init(text: String, ranges: [ProtectedRange]) {
        let string = text as NSString
        var segments: [Segment] = []
        var end = 0
        for protected in ranges.sorted(by: { $0.range.location < $1.range.location }) {
            let range = protected.range
            guard range.location >= end, range.length > 0, range.location >= 0, NSMaxRange(range) <= string.length else { continue }
            if range.location > end { segments.append(Segment(text: string.substring(with: NSRange(location: end, length: range.location - end)), id: nil)) }
            segments.append(Segment(text: string.substring(with: range), id: protected.id))
            end = NSMaxRange(range)
        }
        if end < string.length { segments.append(Segment(text: string.substring(from: end), id: nil)) }
        self.segments = segments
    }

    public func restore(translations: [String]) -> (text: String, ranges: [ProtectedRange]) {
        precondition(translations.count == segments.count)
        var text = ""
        var ranges: [ProtectedRange] = []
        for (index, segment) in segments.enumerated() {
            let value = segment.id == nil ? translations[index] : segment.text
            if let id = segment.id { ranges.append(ProtectedRange(range: NSRange(location: text.utf16.count, length: value.utf16.count), id: id)) }
            text += value
        }
        return (text, ranges)
    }

    public static func literalLinkRanges(in text: String) -> [NSRange] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).map { $0.range }
    }
}

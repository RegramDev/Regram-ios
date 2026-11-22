import Foundation

public enum RGMentionReplacementPolicy {
    public struct Replacement {
        public let range: Range<Int>
        public let text: String
        public init(range: Range<Int>, text: String) { self.range = range; self.text = text }
    }
    public static func replacing(_ text: String, replacements: [Replacement]) -> String {
        let result = NSMutableString(string: text)
        for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceCharacters(in: NSRange(location: replacement.range.lowerBound, length: replacement.range.count), with: replacement.text)
        }
        return result as String
    }
    /// Telegram entity offsets are UTF-16, including emoji and CJK text surrounding a mention.
    public static func remap(_ range: Range<Int>, replacements: [Replacement]) -> Range<Int> {
        func offset(_ value: Int, end: Bool) -> Int {
            var delta = 0
            for replacement in replacements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                if value >= replacement.range.upperBound { delta += replacement.text.utf16.count - replacement.range.count }
                else if value > replacement.range.lowerBound { return replacement.range.lowerBound + delta + (end ? replacement.text.utf16.count : 0) }
                else { break }
            }
            return value + delta
        }
        return offset(range.lowerBound, end: false)..<offset(range.upperBound, end: true)
    }
}

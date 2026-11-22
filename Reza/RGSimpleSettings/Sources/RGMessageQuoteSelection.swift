// MARK: Regram
import Foundation

/// Quote offsets belong to the stored message, before display-only pangu spaces.
public struct RGMessageQuoteSelection {
    public let range: NSRange
    public let text: String

    public static func resolve(_ range: NSRange, in text: String, insertedUtf16Offsets: [Int] = [], expectedSelectionText: String? = nil) -> RGMessageQuoteSelection? {
        let originalLength = text.utf16.count
        let (displayLength, overflow) = originalLength.addingReportingOverflow(insertedUtf16Offsets.count)
        guard !overflow, isValid(range, length: displayLength) else { return nil }
        if let expectedSelectionText {
            guard insertedUtf16Offsets.allSatisfy({ $0 >= 0 && $0 <= originalLength }), insertedUtf16Offsets == insertedUtf16Offsets.sorted() else { return nil }
            let displayText = NSMutableString(string: text)
            for offset in insertedUtf16Offsets.reversed() { displayText.insert(" ", at: offset) }
            guard displayText.substring(with: range) == expectedSelectionText else { return nil }
        }
        let mapped = RGFeaturePangu.reverseTransformRange(range, insertedUtf16Offsets: insertedUtf16Offsets, originalLength: originalLength)
        return validated(mapped, in: text)
    }

    /// Reject stale selections rather than clipping them into a different quote.
    public static func validated(_ range: NSRange, in text: String, expectedText: String? = nil) -> RGMessageQuoteSelection? {
        let string = text as NSString
        guard isValid(range, length: string.length),
              isUTF16Boundary(range.location, in: string), isUTF16Boundary(NSMaxRange(range), in: string) else { return nil }
        let selectedText = string.substring(with: range)
        guard expectedText == nil || selectedText == expectedText else { return nil }
        return RGMessageQuoteSelection(range: range, text: selectedText)
    }

    private static func isValid(_ range: NSRange, length: Int) -> Bool {
        return range.location >= 0 && range.location <= length && range.length > 0 && range.length <= length - range.location
    }

    private static func isUTF16Boundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset > 0 && offset < text.length else { return true }
        return !(0xd800 ... 0xdbff).contains(text.character(at: offset - 1)) || !(0xdc00 ... 0xdfff).contains(text.character(at: offset))
    }
}

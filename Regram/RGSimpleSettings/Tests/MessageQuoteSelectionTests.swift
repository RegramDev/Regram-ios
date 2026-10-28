import Foundation

@main enum MessageQuoteSelectionTests {
    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ reason: String) {
            precondition(value, reason)
            checks += 1
        }
        let original = "测试ABC"
        let display = RGFeaturePangu.transform(original)
        let full = NSRange(location: 0, length: display.text.utf16.count)
        expect(display.text == "测试 ABC" && full.length > original.utf16.count, "Reproduce b34637's out-of-bounds display selection")
        let selected = RGMessageQuoteSelection.resolve(full, in: original, insertedUtf16Offsets: display.insertedUtf16Offsets)
        expect(selected?.text == original && selected?.range == NSRange(location: 0, length: 5), "Quote the original text with original offsets")
        let suffix = (display.text as NSString).range(of: "ABC")
        let selectedSuffix = RGMessageQuoteSelection.resolve(suffix, in: original, insertedUtf16Offsets: display.insertedUtf16Offsets)
        expect(selectedSuffix?.text == "ABC" && selectedSuffix?.range.location == 2, "A suffix at the end must not index the shorter original with display offsets")
        expect(RGMessageQuoteSelection.validated(full, in: original) == nil, "The controller must reject unmapped display offsets")
        expect(RGMessageQuoteSelection.resolve(full, in: original, insertedUtf16Offsets: display.insertedUtf16Offsets, expectedSelectionText: display.text)?.text == original, "The rendered selection must match the stored source after spacing")
        expect(RGMessageQuoteSelection.resolve(full, in: original, insertedUtf16Offsets: display.insertedUtf16Offsets, expectedSelectionText: "another") == nil, "Reject a selection from replacement, translated or summarized content")
        expect(RGMessageQuoteSelection.resolve(NSRange(location: 2, length: 1), in: original, insertedUtf16Offsets: display.insertedUtf16Offsets) == nil, "Selecting only an inserted space must not quote a different character")
        for range in [NSRange(location: 0, length: 0), NSRange(location: -1, length: 1), NSRange(location: 0, length: -1), NSRange(location: NSNotFound, length: 1), NSRange(location: 1, length: Int.max), NSRange(location: Int.max, length: Int.max)] {
            expect(RGMessageQuoteSelection.resolve(range, in: original) == nil, "Malformed ranges must be rejected without arithmetic overflow")
        }
        expect(RGMessageQuoteSelection.validated(NSRange(location: 0, length: 2), in: "new", expectedText: "ol") == nil, "An edit of the same length must not produce a different quote")
        expect(RGMessageQuoteSelection.validated(NSRange(location: 0, length: 5), in: "new", expectedText: "older") == nil, "A shorter edit must not crash")
        expect(RGMessageQuoteSelection.validated(NSRange(location: 0, length: 2), in: "😀A")?.text == "😀", "Use UTF-16 offsets for emoji")
        expect(RGMessageQuoteSelection.validated(NSRange(location: 1, length: 1), in: "😀A") == nil, "Do not split a surrogate pair")
        expect(RGMessageQuoteSelection.resolve(NSRange(location: 0, length: 1), in: "") == nil, "An emptied message must produce a plain reply")
        for text in ["plain text", "中文ABC测试123", "😀中文ABC", "e\u{301}测试123", "中文\nABC", "中A文B"] {
            let transform = RGFeaturePangu.transform(text)
            let range = NSRange(location: 0, length: transform.text.utf16.count)
            let value = RGMessageQuoteSelection.resolve(range, in: text, insertedUtf16Offsets: transform.insertedUtf16Offsets)
            expect(value?.text == text && value?.range.length == text.utf16.count, "Full selections preserve original Unicode text")
        }
        print("Message quote selection: \(checks) checks passed (pangu, UTF-16, edits and invalid ranges).")
    }
}

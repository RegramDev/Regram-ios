import Foundation

@main enum LinkPlanChecks {
    static func main() {
        let input = "😀 Read Docs and https://example.com/中文?q=a&b=2."
        let doc = (input as NSString).range(of: "Docs")
        let url = (input as NSString).range(of: "https://example.com/中文?q=a&b=2")
        let plan = RGTranslationLinkPlan(text: input, ranges: [.init(range: doc, id: 7), .init(range: url, id: 9)])
        let restored = plan.restore(translations: ["😀 阅读 ", "WRONG LABEL", " 和 ", "BROKEN URL", "。"])
        assert(restored.text == "😀 阅读 Docs 和 https://example.com/中文?q=a&b=2。")
        assert(restored.ranges.map(\.id) == [7, 9])
        for (actual, expected) in zip(restored.ranges, ["Docs", "https://example.com/中文?q=a&b=2"]) {
            assert((restored.text as NSString).substring(with: actual.range) == expected)
        }
        let only = RGTranslationLinkPlan(text: "https://t.me/user", ranges: [.init(range: NSRange(location: 0, length: 17), id: 0)])
        assert(only.restore(translations: ["bad"]).text == "https://t.me/user")
        let literal = RGTranslationLinkPlan.literalLinkRanges(in: "Visit https://example.com and name@example.com")
        assert(literal.count == 2)
        let nestedText = "😀 Read Docs now"
        let nested = RGTranslationLinkPlan(text: nestedText, ranges: [
            .init(range: NSRange(location: 3, length: 13), id: 0),
            .init(range: NSRange(location: 8, length: 4), id: 1),
            .init(range: NSRange(location: 8, length: 4), id: 2)
        ], protectedIds: [1])
        let translated = nested.restore(translations: nested.segments.map { $0.id == nil ? $0.text.replacingOccurrences(of: "Read ", with: "阅读 ").replacingOccurrences(of: " now", with: " 现在") : "BROKEN" })
        assert(translated.text == "😀 阅读 Docs 现在")
        assert(translated.ranges.count == 3)
        assert((translated.text as NSString).substring(with: translated.ranges.first(where: { $0.id == 0 })!.range) == "阅读 Docs 现在")
        for id in [1, 2] { assert((translated.text as NSString).substring(with: translated.ranges.first(where: { $0.id == id })!.range) == "Docs") }
        let overlap = RGTranslationLinkPlan(text: "abcdef", ranges: [.init(range: NSRange(location: 0, length: 4), id: 0), .init(range: NSRange(location: 2, length: 4), id: 1)])
        let unchanged = overlap.restore(translations: overlap.segments.map { _ in "wrong" })
        assert(unchanged.text == "abcdef" && unchanged.ranges.count == 2)
        let invalid = RGTranslationLinkPlan(text: "hello", ranges: [.init(range: NSRange(location: Int.max, length: Int.max), id: 0)])
        assert(invalid.restore(translations: ["你好"]).text == "你好")
        let empty = RGTranslationLinkPlan(text: "", ranges: [])
        assert(empty.restore(translations: []).text.isEmpty)
        let whitespace = RGTranslationLinkPlan(text: "\n Hello \t", ranges: [])
        assert(whitespace.restore(translations: ["你好"]).text == "\n 你好 \t")
        let brokenSurrogate = RGTranslationLinkPlan(text: "😀 hello", ranges: [.init(range: NSRange(location: 1, length: 1), id: 0)])
        assert(brokenSurrogate.restore(translations: ["😀 你好"]).text == "😀 你好")
        print("Translation checks passed: links, labels, code/identifier protection, UTF-16, nested/overlapping formatting, invalid ranges and empty input")
    }
}

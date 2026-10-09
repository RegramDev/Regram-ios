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
        print("Translation link plan checks passed: literal and formatted links, UTF-16 ranges, labels and addresses")
    }
}

import Foundation

@main private enum MentionReplacementPolicyTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
    static func main() {
        let original = "😀 @alice 你好 @bob!"
        let first = (original as NSString).range(of: "@alice")
        let second = (original as NSString).range(of: "@bob")
        let replacements: [RGMentionReplacementPolicy.Replacement] = [
            .init(range: first.location..<(first.location + first.length), text: "艾丽丝 🎉"),
            .init(range: second.location..<(second.location + second.length), text: "Robert")
        ]
        let updated = RGMentionReplacementPolicy.replacing(original, replacements: replacements)
        expect(updated == "😀 艾丽丝 🎉 你好 Robert!", "Mixed CJK and emoji messages must preserve surrounding text")
        for (range, label) in [(first, "艾丽丝 🎉"), (second, "Robert")] {
            let mapped = RGMentionReplacementPolicy.remap(range.location..<(range.location + range.length), replacements: replacements)
            expect((updated as NSString).substring(with: NSRange(location: mapped.lowerBound, length: mapped.count)) == label, "Native mention entities must cover their entire replacement")
        }
        let quote = first.location..<(second.location + second.length)
        let mapped = RGMentionReplacementPolicy.remap(quote, replacements: replacements)
        expect((updated as NSString).substring(with: NSRange(location: mapped.lowerBound, length: mapped.count)) == "艾丽丝 🎉 你好 Robert", "Formatting around multiple mentions must survive length changes")
        let end = (original as NSString).length - 1
        let punctuation = RGMentionReplacementPolicy.remap(end..<(end + 1), replacements: replacements)
        expect((updated as NSString).substring(with: NSRange(location: punctuation.lowerBound, length: punctuation.count)) == "!", "Entities after replacements must shift by UTF-16 length")
        expect(RGMentionReplacementPolicy.replacing(original, replacements: []) == original, "Unresolved usernames must keep their original text")
        let base = RGFontConfiguration(family: "inter", messages: true, interface: false, importedChinese: "中文", assetsRevision: 1)
        let refreshed = RGFontConfiguration(family: "inter", messages: true, interface: false, importedChinese: "中文", assetsRevision: 2)
        expect(base.cacheKey(for: .messages) != refreshed.cacheKey(for: .messages), "Completing a download must invalidate cached fallback fonts")
        expect(base.cacheKey(for: .interface) == refreshed.cacheKey(for: .interface), "Disabled areas must retain their system cache")
        expect(base.importedFont(for: .messages, chinese: true) == "中文" && base.importedFont(for: .system, chinese: true).isEmpty, "Imported CJK fonts must respect scope and protected system fonts")
        print("Mention replacement and downloaded-font cache checks passed")
    }
}

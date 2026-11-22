import Foundation
import CoreText

@main
private enum FontCascadeTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func load(_ filename: String, weight: Int? = nil) -> CTFont {
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(filename)
        expect(FileManager.default.fileExists(atPath: url.path), "Missing resource: \(filename)")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        var descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor])[0]
        if let weight {
            descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: weight)]] as CFDictionary)
        }
        return CTFontCreateWithFontDescriptor(descriptor, 19, nil)
    }
    static func main() {
        var combinations = 0
        for bold in [false, true] {
            let chineseFonts = [
                load(bold ? "IBMPlexSansSC-Bold.ttf" : "IBMPlexSansSC-Regular.ttf"),
                load("NotoSerifSC-Variable.ttf", weight: bold ? 700 : 400)
            ]
            for family in ["JetBrainsMono", "Inter", "Lora"] {
                let latin = load("\(family)-\(bold ? "Bold" : "Regular").ttf")
                for chinese in chineseFonts {
                    let composed = RGFontCascade.font(latin: latin, chinese: chinese)
                    let text = "Hello 中文漢字，。Ａ１２ 123 ! 😀"
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): composed]))
                    var sawLatin = false, sawChinese = false, sawEmoji = false
                    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                        let attributes = CTRunGetAttributes(run) as NSDictionary
                        let font = attributes[kCTFontAttributeName] as! CTFont
                        let name = CTFontCopyPostScriptName(font) as String
                        let range = CTRunGetStringRange(run)
                        let substring = (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                        if substring.unicodeScalars.contains(where: { RGFontCascade.chineseCharacters.contains($0) }) {
                            sawChinese = true
                            expect(name == CTFontCopyPostScriptName(chinese) as String, "Chinese or full-width punctuation used the wrong face: \(substring) → \(name)")
                        }
                        if substring.rangeOfCharacter(from: .alphanumerics.subtracting(RGFontCascade.chineseCharacters)) != nil {
                            sawLatin = true
                            expect(name == CTFontCopyPostScriptName(latin) as String, "English/digits must retain their own face: \(substring) → \(name)")
                        }
                        if substring.contains("😀") {
                            sawEmoji = true
                            expect(name.contains("Emoji"), "Emoji must retain system color rendering")
                        }
                    }
                    expect(sawLatin && sawChinese && sawEmoji, "Mixed text must exercise all three scripts")
                    expect(CTLineGetTypographicBounds(line, nil, nil, nil).isFinite, "Mixed-script geometry must remain valid")
                    combinations += 1
                }
            }
        }
        for scalar in [0x4e2d, 0x3001, 0xff21, 0x20000, 0x31350] {
            expect(RGFontCascade.chineseCharacters.contains(UnicodeScalar(scalar)!), "Chinese coverage must include punctuation and supplementary Han")
        }
        for scalar in [0x41, 0x31, 0x21, 0x1f600] {
            expect(!RGFontCascade.chineseCharacters.contains(UnicodeScalar(scalar)!), "ASCII/emoji must stay out of the Chinese font")
        }
        let regular = load("NotoSerifSC-Variable.ttf", weight: 400)
        let bold = load("NotoSerifSC-Variable.ttf", weight: 700)
        expect((CTFontCopyVariation(regular) as NSDictionary?) != (CTFontCopyVariation(bold) as NSDictionary?), "Noto Serif weight axis must apply")
        print("CoreText mixed-script checks passed: \(combinations) Latin/Chinese/style combinations, punctuation, digits, emoji and variable weight")
    }
}

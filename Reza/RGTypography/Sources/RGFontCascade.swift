import Foundation
import CoreText

/// One font object retains independent Latin and Chinese faces across UIKit and CoreText renderers.
public enum RGFontCascade {
    public static let chineseCharacters: CharacterSet = {
        var result = CharacterSet()
        for range in [0x2e80...0x303f, 0x3100...0x312f, 0x31a0...0x31ef, 0x3400...0x4dbf, 0x4e00...0x9fff, 0xf900...0xfaff, 0xff01...0xff60, 0xffe0...0xffe6, 0x20000...0x323af] {
            result.insert(charactersIn: UnicodeScalar(range.lowerBound)!...UnicodeScalar(range.upperBound)!)
        }
        return result
    }()

    public static func font(latin: CTFont, chinese: CTFont) -> CTFont {
        let latinCharacters = (CTFontCopyCharacterSet(latin) as CharacterSet).subtracting(self.chineseCharacters)
        let chineseCharacters = (CTFontCopyCharacterSet(chinese) as CharacterSet).intersection(self.chineseCharacters)
        let chineseDescriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(chinese), [kCTFontCharacterSetAttribute: chineseCharacters as CFCharacterSet] as CFDictionary)
        // Restrict both faces: a Chinese font's Latin glyphs must not replace the Latin selection,
        // and full-width punctuation in the primary face must still follow the Chinese selection.
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(latin), [
            kCTFontCharacterSetAttribute: latinCharacters as CFCharacterSet,
            kCTFontCascadeListAttribute: [chineseDescriptor]
        ] as CFDictionary)
        return CTFontCreateCopyWithAttributes(latin, 0.0, nil, descriptor)
    }
}

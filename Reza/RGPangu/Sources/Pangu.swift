import Foundation

// MARK: Regram — pangu spacing ("盘古之白").
//
// Inserts a single space at every boundary between a CJK character and a half-width alphanumeric,
// in either direction: "中文abc" becomes "中文 abc", "abc中文" becomes "abc 中文".
//
// Scope is deliberately narrow. Only CJK <-> [A-Za-z0-9] boundaries are spaced; punctuation and
// symbols are left alone. A wider rule set (the one pangu.js ships) starts producing changes the
// author did not ask for — spacing around brackets, quotes and units — and this runs on text the
// user is about to send, where a false positive is a visibly wrong message rather than a cosmetic
// nuisance. Under-correcting is the safer failure here.
//
// This module has no dependencies on purpose: it is a pure text transform, so it can be reused from
// any layer (composer, captions, bots) without dragging UI types along.
public enum Pangu {
    private static let space: Unicode.Scalar = " "

    /// True at a CJK <-> alphanumeric boundary, in either direction.
    private static func needsSpace(between left: Unicode.Scalar, and right: Unicode.Scalar) -> Bool {
        return (isCJK(left) && isLatinAlphanumeric(right)) || (isLatinAlphanumeric(left) && isCJK(right))
    }

    /// The CJK block list follows pangu.js, plus the astral ideograph extensions that a UTF-16-only
    /// implementation cannot see. Hangul is excluded: Korean already word-separates with spaces, so
    /// treating it as CJK would insert spaces mid-word.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2EFF,      // CJK Radicals Supplement
             0x2F00...0x2FDF,      // Kangxi Radicals
             0x3040...0x309F,      // Hiragana
             0x30A0...0x30FF,      // Katakana
             0x3100...0x312F,      // Bopomofo
             0x3200...0x32FF,      // Enclosed CJK Letters and Months
             0x3400...0x4DBF,      // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF,      // CJK Unified Ideographs
             0xF900...0xFAFF,      // CJK Compatibility Ideographs
             0x20000...0x2FA1F:    // Extensions B-F and Compatibility Supplement
            return true
        default:
            return false
        }
    }

    private static func isLatinAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39,   // 0-9
             0x41...0x5A,   // A-Z
             0x61...0x7A:   // a-z
            return true
        default:
            return false
        }
    }

    /// Plain-text variant, for callers that carry no formatting.
    public static func spaced(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count + 8)

        var previous: Unicode.Scalar?
        for scalar in string.unicodeScalars {
            if let previous, needsSpace(between: previous, and: scalar) {
                result.unicodeScalars.append(space)
            }
            result.unicodeScalars.append(scalar)
            previous = scalar
        }
        return result
    }

    /// Attributed variant, used on the composer's text before entities are derived from it.
    ///
    /// Working on the attributed string rather than on `(text, entities)` is what keeps this simple:
    /// entity offsets are recomputed from attribute runs further down the send path, so inserting a
    /// character here needs no offset arithmetic and cannot desynchronise an entity from its text.
    ///
    /// - Parameters:
    ///   - skippingAttributes: if either character at a boundary carries one of these, no space is
    ///     inserted. Pass the code/monospace keys — a space inserted into code changes the code.
    ///   - nonInheritedAttributes: stripped from the attributes copied onto the inserted space. Pass
    ///     keys whose value describes one specific glyph (a custom emoji) rather than a span of text.
    public static func spaced(
        _ attributedString: NSAttributedString,
        skippingAttributes: [NSAttributedString.Key] = [],
        nonInheritedAttributes: [NSAttributedString.Key] = []
    ) -> NSAttributedString {
        // Each entry is (UTF-16 offset to insert at, UTF-16 offset of the character to inherit from).
        var insertions: [(at: Int, inheritFrom: Int)] = []

        var previous: (scalar: Unicode.Scalar, start: Int)?
        var offset = 0
        for scalar in attributedString.string.unicodeScalars {
            if let previous, needsSpace(between: previous.scalar, and: scalar) {
                insertions.append((at: offset, inheritFrom: previous.start))
            }
            previous = (scalar, offset)
            offset += UTF16.width(scalar)
        }

        if insertions.isEmpty {
            return attributedString
        }

        let result = NSMutableAttributedString(attributedString: attributedString)
        // Back to front: an insertion shifts every offset after it, so consuming them in reverse
        // keeps the offsets computed above valid without re-deriving them.
        for insertion in insertions.reversed() {
            var attributes = result.attributes(at: insertion.inheritFrom, effectiveRange: nil)

            if skippingAttributes.contains(where: { attributes[$0] != nil }) {
                continue
            }
            // `at` is the first character of the right-hand side, which is in range because a boundary
            // always has a character on both sides.
            let followingAttributes = result.attributes(at: insertion.at, effectiveRange: nil)
            if skippingAttributes.contains(where: { followingAttributes[$0] != nil }) {
                continue
            }

            // Inheriting the left-hand run's attributes keeps a formatted span intact — a space added
            // inside a bold phrase stays bold, so the phrase remains one entity instead of splitting
            // into two.
            for key in nonInheritedAttributes {
                attributes.removeValue(forKey: key)
            }

            result.insert(NSAttributedString(string: " ", attributes: attributes), at: insertion.at)
        }

        return result
    }
}

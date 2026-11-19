import Foundation

/// All persisted and returned offsets are UTF-16 offsets into the ORIGINAL text.
public struct RGAdRange: Codable, Equatable, Hashable {
    public let lower: Int
    public let upper: Int
    public init(_ lower: Int, _ upper: Int) { self.lower = lower; self.upper = upper }
    public var nsRange: NSRange { NSRange(location: lower, length: max(0, upper - lower)) }
    public func intersects(_ other: Self) -> Bool { lower < other.upper && other.lower < upper }
    public func contains(_ other: Self) -> Bool { lower <= other.lower && upper >= other.upper }
}

public struct RGAdEntity: Codable, Equatable, Hashable {
    public enum Kind: String, Codable { case format, link, mention, customEmoji, code, quote }
    public let range: RGAdRange
    public let kind: Kind
    /// Opaque format/custom-emoji identifiers or the actual link target, never fetched.
    public let value: String?
    public init(range: RGAdRange, kind: Kind, value: String? = nil) {
        self.range = range; self.kind = kind; self.value = value
    }
}

public struct RGAdButton: Codable, Equatable, Hashable {
    public let id: String
    public let title: String
    /// Only URL buttons have a target. Callbacks and other actions stay opaque.
    public let target: String?
    public init(id: String, title: String, target: String? = nil) {
        self.id = id; self.title = title; self.target = target
    }
}

public struct RGAdInput: Codable, Equatable, Hashable {
    public let text: String
    public let peerId: Int64?
    public let entities: [RGAdEntity]
    public let buttons: [[RGAdButton]]
    public let hasMedia: Bool
    public let previewTarget: String?

    private enum CodingKeys: String, CodingKey {
        case text, peerId, entities, buttons, hasMedia, previewTarget
    }

    public init(text: String, peerId: Int64? = nil, entities: [RGAdEntity] = [], buttons: [[RGAdButton]] = [], hasMedia: Bool = false, previewTarget: String? = nil) {
        self.text = text; self.peerId = peerId
        self.entities = rgAdAlignEntities(entities, in: text)
        self.buttons = buttons; self.hasMedia = hasMedia; self.previewTarget = previewTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        self.text = text
        self.peerId = try container.decodeIfPresent(Int64.self, forKey: .peerId)
        self.entities = rgAdAlignEntities(try container.decode([RGAdEntity].self, forKey: .entities), in: text)
        self.buttons = try container.decode([[RGAdButton]].self, forKey: .buttons)
        self.hasMedia = try container.decode(Bool.self, forKey: .hasMedia)
        self.previewTarget = try container.decodeIfPresent(String.self, forKey: .previewTarget)
    }
}

/// Explicitly supplied rules only; there is no bundled blacklist or network subscription.
public struct RGAdRule: Codable, Equatable {
    public enum Kind: String, Codable { case literal, regex, target }
    public enum Scope: String, Codable { case match, paragraph }
    public let pattern: String
    public let kind: Kind
    public let scope: Scope
    public let peerId: Int64?
    public init(_ pattern: String, kind: Kind = .literal, scope: Scope = .paragraph, peerId: Int64? = nil) {
        self.pattern = pattern; self.kind = kind; self.scope = scope; self.peerId = peerId
    }
}

public struct RGAdPrediction: Codable, Equatable {
    public let range: RGAdRange
    /// Minimum model score across the supporting windows/context views; not calibrated accuracy.
    public let confidence: Double
    public init(range: RGAdRange, confidence: Double) { self.range = range; self.confidence = confidence }
}

public struct RGAdProjection: Codable, Equatable {
    public enum Disposition: String, Codable { case keep, trim, hide }
    public let disposition: Disposition
    public let text: String
    public let entities: [RGAdEntity]
    public let buttons: [[RGAdButton]]
    public let removedRanges: [RGAdRange]
    public let removedButtonIds: [String]
    public let hideLinkPreview: Bool

    public init(disposition: Disposition, text: String, entities: [RGAdEntity], buttons: [[RGAdButton]], removedRanges: [RGAdRange], removedButtonIds: [String], hideLinkPreview: Bool) {
        self.disposition = disposition; self.text = text; self.entities = entities; self.buttons = buttons
        self.removedRanges = removedRanges; self.removedButtonIds = removedButtonIds; self.hideLinkPreview = hideLinkPreview
    }
}

public enum RGAdFilterError: Error, Equatable {
    case invalidInput, invalidModel, unsupportedTokenizer, inputTooLong, invalidPrediction, budgetExceeded
}

private func rgAdBoundaryList(_ text: String) -> [Int] {
    var result: [Int] = [0]
    result.reserveCapacity(text.count + 1)
    var offset = 0
    for character in text { offset += String(character).utf16.count; result.append(offset) }
    return result
}

private func rgAdSearchBoundary(_ value: Int, in boundaries: [Int], floor: Bool) -> Int {
    var lo = 0, hi = boundaries.count - 1
    while lo < hi {
        if floor {
            let mid = (lo + hi + 1) / 2
            if boundaries[mid] <= value { lo = mid } else { hi = mid - 1 }
        } else {
            let mid = (lo + hi) / 2
            if boundaries[mid] >= value { hi = mid } else { lo = mid + 1 }
        }
    }
    return boundaries[lo]
}

/// Snaps valid in-bounds UTF-16 entity ranges that split inside a multi-codeunit grapheme
/// cluster (such as an emoji followed by U+FE0F) onto enclosing Swift `Character` boundaries.
func rgAdAlignEntities(_ entities: [RGAdEntity], in text: String) -> [RGAdEntity] {
    guard !entities.isEmpty else { return entities }
    let boundaries = rgAdBoundaryList(text)
    let boundarySet = Set(boundaries)
    let length = boundaries[boundaries.count - 1]
    return entities.map { entity in
        let lower = entity.range.lower, upper = entity.range.upper
        guard lower >= 0, upper > lower, upper <= length else { return entity }
        if boundarySet.contains(lower) && boundarySet.contains(upper) { return entity }
        let alignedLower = rgAdSearchBoundary(lower, in: boundaries, floor: true)
        let alignedUpper = rgAdSearchBoundary(upper, in: boundaries, floor: false)
        guard alignedUpper > alignedLower else { return entity }
        return RGAdEntity(range: RGAdRange(alignedLower, alignedUpper), kind: entity.kind, value: entity.value)
    }
}

func rgAdBoundaries(_ text: String) -> Set<Int> {
    Set(rgAdBoundaryList(text))
}

func rgAdValid(_ range: RGAdRange, boundaries: Set<Int>) -> Bool {
    range.lower >= 0 && range.upper > range.lower && boundaries.contains(range.lower) && boundaries.contains(range.upper)
}

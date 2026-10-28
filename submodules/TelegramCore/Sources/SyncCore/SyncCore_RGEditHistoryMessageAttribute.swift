import Foundation
import Postbox

// MARK: Regram — edit history.
//
// The server keeps only the current text of an edited message. When an edit arrives (ours or
// someone else's) and "Save edit history" is on, the text it replaces is appended here, so the
// message carries every earlier version it had while this device was watching. Edits that happened
// before this device saw the message, or while its history was refetched wholesale, are unknown.
public final class RGEditHistoryEntry: PostboxCoding, Equatable {
    public let text: String
    public let entities: [MessageTextEntity]
    /// When this version was published: the message date for the original, else its edit date.
    public let date: Int32
    public let image: TelegramMediaImage?
    public let imageData: Data?
    public let imageHasSpoiler: Bool
    public let richText: RichTextMessageAttribute?
    public static let maximumImageBytes = 8 * 1024 * 1024

    public init(text: String, entities: [MessageTextEntity], date: Int32, image: TelegramMediaImage? = nil, imageData: Data? = nil, imageHasSpoiler: Bool = false, richText: RichTextMessageAttribute? = nil) {
        self.text = text
        self.entities = entities
        self.date = date
        self.image = image
        self.imageData = imageData.flatMap { $0.count <= Self.maximumImageBytes ? $0 : nil }
        self.imageHasSpoiler = imageHasSpoiler
        self.richText = richText.map { RichTextMessageAttribute(instantPage: $0.instantPage, fullInstantPage: $0.fullInstantPage) }
    }

    public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("e")
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
        self.image = decoder.decodeObjectForKey("im") as? TelegramMediaImage
        self.imageData = decoder.decodeDataForKey("ib").flatMap { $0.count <= Self.maximumImageBytes ? $0 : nil }
        self.imageHasSpoiler = decoder.decodeInt32ForKey("sp", orElse: 0) != 0
        self.richText = decoder.decodeObjectForKey("rt", decoder: { RichTextMessageAttribute(decoder: $0) }) as? RichTextMessageAttribute
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeObjectArray(self.entities, forKey: "e")
        encoder.encodeInt32(self.date, forKey: "d")
        if let image { encoder.encodeObject(image, forKey: "im") } else { encoder.encodeNil(forKey: "im") }
        if let imageData { encoder.encodeData(imageData, forKey: "ib") } else { encoder.encodeNil(forKey: "ib") }
        encoder.encodeInt32(imageHasSpoiler ? 1 : 0, forKey: "sp")
        if let richText { encoder.encodeObject(richText, forKey: "rt") } else { encoder.encodeNil(forKey: "rt") }
    }

    public static func ==(lhs: RGEditHistoryEntry, rhs: RGEditHistoryEntry) -> Bool {
        return lhs.text == rhs.text && lhs.entities == rhs.entities && lhs.date == rhs.date && lhs.image?.imageId == rhs.image?.imageId && lhs.imageData == rhs.imageData && lhs.imageHasSpoiler == rhs.imageHasSpoiler && lhs.richText == rhs.richText
    }
}

public class RGEditHistoryMessageAttribute: MessageAttribute {
    /// Bounds the stored history of one message; the oldest versions after the original go first.
    public static let maxEntries = 50
    public static let maximumImageHistoryBytes = 32 * 1024 * 1024

    /// Earlier versions, oldest first. The current text is the message's own.
    public let entries: [RGEditHistoryEntry]

    public init(entries: [RGEditHistoryEntry]) {
        self.entries = entries
    }

    required public init(decoder: PostboxDecoder) {
        self.entries = decoder.decodeObjectArrayWithDecoderForKey("v")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.entries, forKey: "v")
    }

    /// Appends `entry`, keeping the original version and dropping the oldest edits past the cap.
    public func withAppendedEntry(_ entry: RGEditHistoryEntry) -> RGEditHistoryMessageAttribute {
        var entries = self.entries
        if entries.last == entry {
            return self
        }
        entries.append(entry)
        if entries.count > RGEditHistoryMessageAttribute.maxEntries {
            entries.remove(at: 1)
        }
        // Keep the original and recent image previews within a per-message storage budget.
        var totalBytes = entries.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        for index in entries.indices.dropFirst() where totalBytes > Self.maximumImageHistoryBytes {
            let old = entries[index]
            guard let data = old.imageData else { continue }
            totalBytes -= data.count
            entries[index] = RGEditHistoryEntry(text: old.text, entities: old.entities, date: old.date, image: old.image, imageHasSpoiler: old.imageHasSpoiler, richText: old.richText)
        }
        return RGEditHistoryMessageAttribute(entries: entries)
    }

    public func withImageData(_ data: Data, at index: Int) -> RGEditHistoryMessageAttribute {
        guard entries.indices.contains(index), data.count <= RGEditHistoryEntry.maximumImageBytes else { return self }
        var updated = entries
        let entry = updated.remove(at: index)
        updated.insert(RGEditHistoryEntry(text: entry.text, entities: entry.entities, date: entry.date, image: entry.image, imageData: data, imageHasSpoiler: entry.imageHasSpoiler, richText: entry.richText), at: index)
        // Reuse the same budget enforcement without introducing a duplicate version.
        let last = updated.removeLast()
        return RGEditHistoryMessageAttribute(entries: updated).withAppendedEntry(last)
    }
}

public extension Message {
    var rgEditHistory: RGEditHistoryMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? RGEditHistoryMessageAttribute, !attribute.entries.isEmpty {
                return attribute
            }
        }
        return nil
    }
}

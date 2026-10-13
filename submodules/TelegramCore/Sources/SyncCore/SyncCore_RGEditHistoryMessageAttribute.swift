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

    public init(text: String, entities: [MessageTextEntity], date: Int32) {
        self.text = text
        self.entities = entities
        self.date = date
    }

    public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("e")
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeObjectArray(self.entities, forKey: "e")
        encoder.encodeInt32(self.date, forKey: "d")
    }

    public static func ==(lhs: RGEditHistoryEntry, rhs: RGEditHistoryEntry) -> Bool {
        return lhs.text == rhs.text && lhs.entities == rhs.entities && lhs.date == rhs.date
    }
}

public class RGEditHistoryMessageAttribute: MessageAttribute {
    /// Bounds the stored history of one message; the oldest versions after the original go first.
    public static let maxEntries = 50

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
        return RGEditHistoryMessageAttribute(entries: entries)
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

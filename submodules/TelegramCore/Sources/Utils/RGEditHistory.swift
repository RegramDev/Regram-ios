import Foundation
import Postbox
import SwiftSignalKit
import RGSimpleSettings

// MARK: Regram — local message attributes across a server rewrite.
//
// An edit (ours, confirmed in RequestEditMessage, or anyone's, replayed as `.EditMessage`) replaces
// the stored message with the server's copy. With "Save edit history" on, the text being replaced is
// appended to the history here, where both versions are at hand. The local attributes would also
// survive through the seed configuration's `mergeMessageAttributes`, which covers every rewrite of
// an existing message, refetches included; carrying them here keeps the updated history in place
// of the stale one.
func rgCarryOverLocalMessageAttributes(previousMessage: Message, updatedText: String, updatedAttributes: [MessageAttribute], updatedMedia: [Media], mediaBox: MediaBox) -> [MessageAttribute] {
    var attributes = updatedAttributes.filter { !($0 is RGRevokedMessageAttribute || $0 is RGEditHistoryMessageAttribute) }
    // Keep consumed local expiries consumed when unrelated server metadata is refreshed.
    attributes = attributes.map { attribute in
        if let ttl = attribute as? AutoremoveTimeoutMessageAttribute,
           let old = previousMessage.attributes.compactMap({ $0 as? AutoremoveTimeoutMessageAttribute }).first,
           old.isLocallyPreserved, old.timeout == ttl.timeout, old.countdownBeginTime == ttl.countdownBeginTime { return old }
        if let ttl = attribute as? AutoclearTimeoutMessageAttribute,
           let old = previousMessage.attributes.compactMap({ $0 as? AutoclearTimeoutMessageAttribute }).first,
           old.isLocallyPreserved, old.timeout == ttl.timeout, old.countdownBeginTime == ttl.countdownBeginTime { return old }
        return attribute
    }

    if let revoked = previousMessage.attributes.first(where: { $0 is RGRevokedMessageAttribute }) {
        attributes.append(revoked)
    }
    var editHistory = previousMessage.attributes.first(where: { $0 is RGEditHistoryMessageAttribute }) as? RGEditHistoryMessageAttribute
    if RGSimpleSettings.shared.saveEditHistory, let previousVersion = rgEditHistoryPreviousVersion(previousMessage: previousMessage, updatedText: updatedText, updatedAttributes: updatedAttributes, updatedMedia: updatedMedia, mediaBox: mediaBox) {
        editHistory = (editHistory ?? RGEditHistoryMessageAttribute(entries: [])).withAppendedEntry(previousVersion)
    }
    if let editHistory {
        attributes.append(editHistory)
    }
    return attributes
}

/// The version an edit replaces, or nil when the text is left alone. The server also re-sends
/// messages for reasons other than an edit (reactions, link previews, views), so a change of
/// formatting alone counts only together with a newer edit date.
private func rgEditHistoryPreviousVersion(previousMessage: Message, updatedText: String, updatedAttributes: [MessageAttribute], updatedMedia: [Media], mediaBox: MediaBox) -> RGEditHistoryEntry? {
    let previousEntities = previousMessage.textEntitiesAttribute?.entities ?? []
    let previousEditDate = (previousMessage.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date
    let previousRich = previousMessage.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute
    let updatedRich = updatedAttributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute
    let oldImage = previousMessage.media.compactMap { $0 as? TelegramMediaImage }.first
    let newImage = updatedMedia.compactMap { $0 as? TelegramMediaImage }.first
    let spoilerChanged = previousMessage.attributes.contains { $0 is MediaSpoilerMessageAttribute } != updatedAttributes.contains { $0 is MediaSpoilerMessageAttribute }
    let imageChanged = oldImage?.imageId != newImage?.imageId || (oldImage != nil && spoilerChanged)
    if previousMessage.text == updatedText && !imageChanged {
        let updatedEntities = (updatedAttributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
        let updatedEditDate = (updatedAttributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date
        // Full-page hydration is a cache update; only a newer edit with changed authored blocks counts.
        let richChanged = previousRich?.instantPage != updatedRich?.instantPage
        guard previousEntities != updatedEntities || richChanged, let updatedEditDate, updatedEditDate > (previousEditDate ?? 0) else {
            return nil
        }
    }
    let retainImage = previousMessage.id.peerId.namespace != Namespaces.Peer.SecretChat && !previousMessage.containsSecretMedia && !previousMessage.isCopyProtected()
    let image = retainImage ? oldImage : nil
    return RGEditHistoryEntry(text: previousMessage.rgTextContent, entities: previousEntities, date: previousEditDate ?? previousMessage.timestamp, image: image, imageData: image.flatMap { rgEditHistoryCachedImageData(image: $0, mediaBox: mediaBox) }, imageHasSpoiler: previousMessage.attributes.contains { $0 is MediaSpoilerMessageAttribute }, richText: previousRich)
}

// MARK: Regram — preserve already downloaded image bytes with the message, outside evictable media cache.
public func rgEditHistoryCachedImageData(image: TelegramMediaImage, mediaBox: MediaBox) -> Data? {
    let representations = image.representations.sorted { Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height) }
    for representation in representations {
        guard let path = mediaBox.completedResourcePath(representation.resource),
              let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
              size.intValue <= RGEditHistoryEntry.maximumImageBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else { continue }
        return data
    }
    return nil
}

public func rgSaveEditHistoryImageData(postbox: Postbox, messageId: MessageId, versionIndex: Int, expectedImageId: MediaId, data: Data) -> Signal<Never, NoError> {
    return postbox.transaction { transaction in
        transaction.updateMessage(messageId, update: { message in
            guard let history = message.rgEditHistory, history.entries.indices.contains(versionIndex), history.entries[versionIndex].image?.imageId == expectedImageId else { return .skip }
            let attributes: [MessageAttribute] = message.attributes.map { $0 is RGEditHistoryMessageAttribute ? history.withImageData(data, at: versionIndex) : $0 }
            return .update(StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media))
        })
    } |> ignoreValues
}

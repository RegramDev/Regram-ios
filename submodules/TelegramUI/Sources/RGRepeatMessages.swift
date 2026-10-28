import Foundation
import TelegramCore
import AccountContext
import SwiftSignalKit

// MARK: Regram — 复读 / 无引用复读, shared by the message menu and double tap.

/// EngineRawMedia that can be re-sent as a brand-new message. Cloud photos and files are sent by their
/// existing id/access_hash, so nothing is re-uploaded, while maps and contacts are plain values.
/// `nil` means the message holds something that only exists as a forward (poll, game, invoice,
/// story, service action) — then only a forward can repeat it. A webpage is skipped rather than
/// rejected: it is the preview of a link in the text and the server regenerates it.
private func rgRepeatableMedia(of message: EngineRawMessage) -> [EngineRawMedia]? {
    var result: [EngineRawMedia] = []
    for media in message.media {
        if media is TelegramMediaWebpage {
            continue
        }
        if media is TelegramMediaImage || media is TelegramMediaFile || media is TelegramMediaMap || media is TelegramMediaContact {
            result.append(media)
        } else {
            return nil
        }
    }
    return result
}

/// What 无引用复读 would send for `messages` (an album when several are given), or nil when one of
/// them can only be forwarded.
func rgRepeatCopyItems(_ messages: [EngineRawMessage]) -> [(message: EngineRawMessage, media: EngineRawMedia?)]? {
    if messages.isEmpty {
        return nil
    }
    var items: [(message: EngineRawMessage, media: EngineRawMedia?)] = []
    for message in messages {
        guard message.id.namespace == Namespaces.Message.Cloud, let media = rgRepeatableMedia(of: message) else {
            return nil
        }
        if media.isEmpty && message.text.isEmpty && !message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
            return nil
        }
        items.append((message, media.first))
    }
    return items
}

/// Re-sends the messages' own content into `peerId` under your name. Unlike a forward this produces
/// an ordinary message with no link back to the original, which is the point of 无引用复读.
func rgSendRepeatCopy(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, items: [(message: EngineRawMessage, media: EngineRawMedia?)], failed: @escaping () -> Void) {
    guard !items.isEmpty else { return }
    let signals: [Signal<RichTextMessageAttribute?, NoError>] = items.map { item in
        guard let rich = item.message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute else { return .single(nil) }
        if (rich.fullInstantPage ?? rich.instantPage).isComplete { return .single(rich) }
        return context.engine.messages.requestFullRichText(id: item.message.id)
    }
    // Do not turn a server preview into a truncated copy, or send only part of a selected album.
    let _ = (combineLatest(signals) |> take(1) |> timeout(20, queue: .mainQueue(), alternate: .single([])) |> deliverOnMainQueue).startStandalone(next: { pages in
        guard pages.count == items.count else { failed(); return }
        var resolved: [EngineMessage.Id: RichTextMessageAttribute] = [:]
        for (index, item) in items.enumerated() where item.message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
            guard let rich = pages[index], (rich.fullInstantPage ?? rich.instantPage).isComplete else { failed(); return }
            resolved[item.message.id] = rich
        }
        rgEnqueueRepeatCopy(context: context, peerId: peerId, threadId: threadId, items: items, richPages: resolved)
    })
}

private func rgEnqueueRepeatCopy(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, items: [(message: EngineRawMessage, media: EngineRawMedia?)], richPages: [EngineMessage.Id: RichTextMessageAttribute]) {
    var enqueued: [EnqueueMessage] = []
    let groupingKey: Int64? = items.count > 1 ? Int64.random(in: Int64.min ... Int64.max) : nil
    for item in items {
        var attributes: [EngineMessage.Attribute] = []
        if let rich = richPages[item.message.id] {
            // Keep authored blocks and embedded media on the normal rich-message send path.
            attributes.append(RichTextMessageAttribute(instantPage: rich.fullInstantPage ?? rich.instantPage, fullInstantPage: nil))
        }
        if let entities = (item.message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities, !entities.isEmpty {
            attributes.append(TextEntitiesMessageAttribute(entities: entities))
        }
        // Custom emoji in the text are entities pointing at files carried alongside the message;
        // without them the copy would render as plain fallback characters.
        var inlineStickers: [EngineMedia.Id: EngineRawMedia] = [:]
        for (mediaId, media) in item.message.associatedMedia {
            if media is TelegramMediaFile {
                inlineStickers[mediaId] = media
            }
        }
        // A `.message` reference (rather than `.standalone`) records where the media came from,
        // which is what lets an expired file reference be revalidated instead of failing the send —
        // and it is what makes sending into *another* chat work at all.
        let mediaReference: AnyMediaReference? = item.media.flatMap { AnyMediaReference.message(message: MessageReference(item.message), media: $0) }
        enqueued.append(.message(text: item.message.text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: []))
    }
    if enqueued.isEmpty {
        return
    }
    let _ = enqueueMessages(account: context.account, peerId: peerId, messages: enqueued).startStandalone()
}

/// 复读: a plain forward straight back into `peerId`, attribution intact.
func rgSendRepeatForward(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, messageIds: [EngineMessage.Id]) {
    let enqueued: [EnqueueMessage] = messageIds.map { id in
        return .forward(source: id, threadId: threadId, grouping: .auto, attributes: [], correlationId: nil)
    }
    if enqueued.isEmpty {
        return
    }
    let _ = enqueueMessages(account: context.account, peerId: peerId, messages: enqueued).startStandalone()
}

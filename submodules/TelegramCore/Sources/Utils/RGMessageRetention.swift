// MARK: Regram — distinguish confirmed server deletion from unavailable history.
import Postbox
import RGSimpleSettings

func rgMarkMessageRevoked(transaction: Transaction, id: MessageId, reason: RGRevokedMessageAttribute.Reason = .revoked) {
    transaction.updateMessage(id, update: { message in
        let old = message.attributes.first(where: { $0 is RGRevokedMessageAttribute }) as? RGRevokedMessageAttribute
        // A later explicit deletion can promote an unavailable record, never the reverse.
        if let old, old.reason == .revoked || old.reason == reason { return .skip }
        var attributes = message.attributes.filter { !($0 is RGRevokedMessageAttribute) }
        attributes.append(RGRevokedMessageAttribute(date: old?.date ?? message.timestamp, reason: reason))
        return .update(StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media))
    })
}

func rgRetainDeletedMessageRange(transaction: Transaction, peerId: PeerId, namespace: MessageId.Namespace, maxId: Int32) -> Bool {
    guard RGSimpleSettings.shared.isAntiRevokeEnabled(forPeer: peerId.toInt64()) else { return false }
    // Query the id index for this peer/range; no full history rendering or database scan.
    for id in transaction.rgMessageIdsInRange(peerId: peerId, namespace: namespace, minId: 1, maxId: maxId) {
        rgMarkMessageRevoked(transaction: transaction, id: id)
    }
    return true
}

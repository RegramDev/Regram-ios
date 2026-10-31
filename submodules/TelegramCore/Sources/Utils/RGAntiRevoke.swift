// MARK: Regram — apply the same sender exclusion to updates and history reconciliation.
import Postbox
import RGSimpleSettings

func rgShouldRetainRevokedMessage(transaction: Transaction, id: MessageId) -> Bool {
    let settings = RGSimpleSettings.shared
    guard settings.isAntiRevokeEnabled(forPeer: id.peerId.toInt64()) else { return false }
    guard settings.antiRevokeIgnoreBots else { return true }
    guard let message = transaction.getMessage(id) else { return true }
    // This switch governs new revocations; leave records retained before it was enabled intact.
    if message.attributes.contains(where: { $0 is RGRevokedMessageAttribute }) { return true }
    // An inline bot attribution is not the sender: keep messages authored by a person.
    if let author = message.author as? TelegramUser {
        return author.botInfo == nil
    }
    // Older incoming private messages can lack their author in the rendered message.
    if message.author == nil, message.flags.contains(.Incoming), id.peerId.namespace == Namespaces.Peer.CloudUser,
       let peer = transaction.getPeer(id.peerId) as? TelegramUser {
        return peer.botInfo == nil
    }
    return true
}

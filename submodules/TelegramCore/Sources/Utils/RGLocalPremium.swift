import Foundation
import Postbox
import SwiftSignalKit
import RGSimpleSettings

// MARK: Regram — local Premium
//
// Makes the app treat the accounts signed in on this device as Premium, so the client-side gates
// open. This is a read-time override on `Peer.isPremium`: nothing is sent to Telegram and no flag
// is written to the database, so switching it off restores the real state immediately. Anything the
// server enforces (sending premium stickers, setting an emoji status, raising real limits, …) still
// needs an actual subscription and will keep failing server-side.

private let rgLocalPremiumAccountPeerIds = Atomic<Set<PeerId>>(value: Set())

/// Registers an account as one of "mine". Called for every account context the app creates, so
/// every logged-in account — not just the active one — is covered.
public func rgRegisterLocalPremiumAccountPeerId(_ peerId: PeerId) {
    let _ = rgLocalPremiumAccountPeerIds.modify { peerIds in
        var peerIds = peerIds
        peerIds.insert(peerId)
        return peerIds
    }
}

/// Whether `peerId` should read back as Premium because of the local switch. False for every peer
/// that is not one of the signed-in accounts, so other users keep their real status.
public func rgIsLocalPremiumPeerId(_ peerId: PeerId) -> Bool {
    // Checked in this order on purpose: `Peer.isPremium` runs for every peer the app renders, and
    // for all of them except the handful of account ids this bails out without touching settings.
    if !rgLocalPremiumAccountPeerIds.with({ peerIds in peerIds.contains(peerId) }) {
        return false
    }
    return RGSimpleSettings.shared.localPremium
}

// MARK: Emoji status
//
// The server silently drops `account.updateEmojiStatus` for an account that is not really Premium
// and then pushes the empty status back (as a `updateUserEmojiStatus` update or with the next user
// fetch), which is what wipes the pick a moment after it is made. So the chosen status is kept here
// and `TelegramUser.emojiStatus` reads it back — the database keeps holding whatever the server
// says, and turning the switch off restores it.

private enum RGLocalEmojiStatusEntry {
    case absent
    case present(PeerEmojiStatus)
}

/// Decoded mirror of the stored JSON, so reading the status does not parse on every access.
private let rgLocalEmojiStatusCache = Atomic<[PeerId: RGLocalEmojiStatusEntry]>(value: [:])

private func rgLocalEmojiStatusKey(_ peerId: PeerId) -> String {
    return "\(peerId.toInt64())"
}

private func rgSetCachedLocalEmojiStatus(peerId: PeerId, entry: RGLocalEmojiStatusEntry) {
    let _ = rgLocalEmojiStatusCache.modify { cache in
        var cache = cache
        cache[peerId] = entry
        return cache
    }
}

/// Remembers the status the user just picked. Does nothing unless local Premium is on and `peerId`
/// is one of the signed-in accounts, so a real Premium account is never pinned to a stale value.
public func rgStoreLocalPremiumEmojiStatus(peerId: PeerId, status: PeerEmojiStatus?) {
    if !rgIsLocalPremiumPeerId(peerId) {
        return
    }

    let key = rgLocalEmojiStatusKey(peerId)
    if let status, let data = try? JSONEncoder().encode(status), let encoded = String(data: data, encoding: .utf8) {
        RGSimpleSettings.shared.localPremiumEmojiStatus[key] = encoded
        rgSetCachedLocalEmojiStatus(peerId: peerId, entry: .present(status))
    } else {
        // Cleared by the user, or not encodable — drop the override and let the real status show.
        RGSimpleSettings.shared.localPremiumEmojiStatus.removeValue(forKey: key)
        rgSetCachedLocalEmojiStatus(peerId: peerId, entry: .absent)
    }
}

/// The status kept for `peerId`, or nil when there is none, it has expired, or the switch is off.
public func rgLocalPremiumEmojiStatus(peerId: PeerId) -> PeerEmojiStatus? {
    if !rgIsLocalPremiumPeerId(peerId) {
        return nil
    }

    let entry: RGLocalEmojiStatusEntry
    if let cached = rgLocalEmojiStatusCache.with({ cache in cache[peerId] }) {
        entry = cached
    } else {
        if let encoded = RGSimpleSettings.shared.localPremiumEmojiStatus[rgLocalEmojiStatusKey(peerId)],
           let data = encoded.data(using: .utf8),
           let status = try? JSONDecoder().decode(PeerEmojiStatus.self, from: data) {
            entry = .present(status)
        } else {
            entry = .absent
        }
        rgSetCachedLocalEmojiStatus(peerId: peerId, entry: entry)
    }

    guard case let .present(status) = entry else {
        return nil
    }
    if let expirationDate = status.expirationDate, expirationDate <= Int32(Date().timeIntervalSince1970) {
        return nil
    }
    return status
}

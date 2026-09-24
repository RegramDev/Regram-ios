import Foundation
import RGSimpleSettings

// MARK: Regram — Ghost mode.
//
// Every switch here suppresses exactly one *outgoing* signal on the network path. Nothing about the
// local state changes: stories still count as seen locally, the composer still shows what you are
// doing. Only the request that would tell the other side is dropped.
//
// Message read receipts are deliberately not among them. A "don't send read receipts" switch
// existed and was removed: local and server read state diverge while it is on, and every later
// read-state validation of such a chat has to cope with that (see `validatePeerReadState`).
//
// The values are read live on each request rather than cached, so toggling a switch takes effect on
// the next network call without a restart.
enum RGGhostMode {
    /// Drops `stories.readStories` and `stories.incrementStoryViews`.
    static var suppressStoryViews: Bool {
        return RGSimpleSettings.shared.ghostDontReadStories
    }

    /// Forces `account.updateStatus` to always report offline.
    static var suppressOnlinePresence: Bool {
        return RGSimpleSettings.shared.ghostDontSendOnline
    }

    /// Drops `messages.setTyping` and `messages.setEncryptedTyping`.
    static var suppressInputActivity: Bool {
        return RGSimpleSettings.shared.ghostDontSendTyping
    }
}

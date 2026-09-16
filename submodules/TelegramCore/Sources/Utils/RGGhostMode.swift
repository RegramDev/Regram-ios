import Foundation
import RGSimpleSettings

// MARK: Regram — Ghost mode.
//
// Every switch here suppresses exactly one *outgoing* signal on the network path. Nothing about the
// local state changes: messages still get marked read locally, stories still count as seen locally,
// the composer still shows what you are doing. Only the request that would tell the other side is
// dropped.
//
// The guiding rule for where these are applied: **passive reporting is suppressed, explicit user
// actions are not.** Opening a chat is passive, so its read receipt is dropped. Tapping "Mark All as
// Read" or "Read All Mentions" is an explicit instruction, so those still reach the server — the
// badge the user just asked to clear has to actually clear.
//
// The values are read live on each request rather than cached, so toggling a switch takes effect on
// the next network call without a restart.
enum RGGhostMode {
    /// Drops `messages.readHistory`, `channels.readHistory`, `messages.readDiscussion` and the
    /// `readMessageContents` "played/viewed" marks for voice, video and TTL media.
    static var suppressReadReceipts: Bool {
        return RGSimpleSettings.shared.ghostDontReadMessages
    }

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

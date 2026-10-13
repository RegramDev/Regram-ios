// MARK: Regram
import Foundation

/// Stable persisted ids for native and Regram message actions. Never rename a raw value.
/// Case order is the default menu order; saved orders retain their existing ids on upgrade.
public enum RGContextMenuItemId: String, CaseIterable, Hashable {
    case viewInChat
    case favoriteSticker
    case saveStickerToCameraRoll
    case shareCallStats
    case rateCall
    case saveNotificationSound
    case increaseSpeed
    case reply
    case sendGift
    case sendMoney
    case repeatForward
    case repeatCopy
    case retry
    case sendScheduledNow
    case editScheduledTime
    case copy
    case translate
    case speak
    case saveMedia
    case saveToFiles
    case sendLogs
    case messageReplies
    case edit
    case editHistory
    case editSuggestedPostMessage
    case editSuggestedPostTime
    case editSuggestedPostPrice
    case createSuggestedPost
    case unvotePoll
    case addTodoTask
    case unpin
    case pin
    case stopPoll
    case copyLink
    case saveGif
    case editSticker
    case viewStickerPack
    case saveToCloud
    case forward
    case forwardNoQuote
    case activateLink
    case report
    case block
    case restrict
    case viewStats
    case viewPollStats
    case factCheck
    case viewInChannel
    case select
    case selectFromUser
    case selectAll
    case delete
    case json
    case addFilter

    /// Regular message actions implemented by Regram. Conditional actions are added only after
    /// the account actually produces them; diagnostics and wallet actions stay out of this UI.
    public static let standardItems: Set<RGContextMenuItemId> = [
        .reply, .repeatForward, .repeatCopy, .copy, .translate, .speak, .edit, .editHistory,
        .pin, .unpin, .copyLink, .forward, .forwardNoQuote, .saveToCloud, .saveMedia,
        .saveToFiles, .favoriteSticker, .saveStickerToCameraRoll, .saveGif, .viewStickerPack,
        .select, .selectFromUser, .delete, .report, .json, .addFilter
    ]

    public var canBeCustomized: Bool {
        switch self {
        case .sendMoney, .sendLogs, .activateLink: return false
        default: return true
        }
    }
}

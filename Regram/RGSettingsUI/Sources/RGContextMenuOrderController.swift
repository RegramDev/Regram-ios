import RGSwiftUI
// MARK: Regram
import RGSimpleSettings
import RGStrings

import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum RGContextMenuOrderSection: Int32 {
    case items
}

/// One row of the message-menu order screen: a managed item with its on/off switch.
///
/// Identity and position are deliberately separate. `stableId` is the item's own id, so the list
/// diff sees a drag as a *move* of the same row rather than as every row changing content;
/// `sortIndex` is what `<` compares, so the displayed order follows the stored arrangement. Folding
/// the two together — which is what `RGItemListUIEntry` does — makes reordering animate as a full
/// rebuild.
private enum RGContextMenuOrderEntry: ItemListNodeEntry {
    case item(sortIndex: Int, id: RGContextMenuItemId, title: String, value: Bool)
    case info(sortIndex: Int, text: String)

    var section: ItemListSectionId {
        return RGContextMenuOrderSection.items.rawValue
    }

    var sortIndex: Int {
        switch self {
        case let .item(sortIndex, _, _, _):
            return sortIndex
        case let .info(sortIndex, _):
            return sortIndex
        }
    }

    var stableId: Int {
        switch self {
        case let .item(_, id, _, _):
            // Offset so it can never collide with the info row.
            return 1 + (RGContextMenuItemId.allCases.firstIndex(of: id) ?? 0)
        case .info:
            return 0
        }
    }

    static func <(lhs: RGContextMenuOrderEntry, rhs: RGContextMenuOrderEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGContextMenuOrderArguments
        switch self {
        case let .item(_, id, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enableInteractiveChanges: true, enabled: true, isReorderable: true, sectionId: self.section, style: .blocks, updated: { updatedValue in
                arguments.setValue(id, updatedValue)
            })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class RGContextMenuOrderArguments {
    let setValue: (RGContextMenuItemId, Bool) -> Void

    init(setValue: @escaping (RGContextMenuItemId, Bool) -> Void) {
        self.setValue = setValue
    }
}

/// Display name for a managed item. Reuses the same strings the menu itself uses, so the settings
/// row and the menu entry can never drift apart.
private func rgContextMenuItemTitle(_ id: RGContextMenuItemId, strings: PresentationStrings) -> String {
    let lang = strings.rgLanguageCode
    switch id {
    case .repeatForward:
        return "Repeat.WithReply".i18n(lang)
    case .repeatCopy:
        return "Repeat.Plain".i18n(lang)
    case .forwardNoQuote:
        return "Repeat.ForwardNoQuote".i18n(lang)
    case .saveToCloud:
        return "ContextMenu.SaveToCloud".i18n(lang)
    case .selectFromUser:
        return "ContextMenu.SelectFromUser".i18n(lang)
    case .restrict:
        return strings.Conversation_ContextMenuBan
    case .report:
        return strings.Conversation_ContextMenuReport
    case .reply:
        return strings.Conversation_ContextMenuReply
    case .pin:
        return strings.Conversation_Pin
    case .saveMedia:
        return strings.Gallery_SaveImage
    case .messageReplies:
        return strings.Conversation_ContextViewThread
    case .viewInChat:
        return strings.SharedMedia_ViewInChat
    case .favoriteSticker:
        return strings.Stickers_AddToFavorites
    case .shareCallStats:
        return strings.Call_ShareStats
    case .rateCall:
        return strings.Call_RateCall
    case .saveNotificationSound:
        return strings.Chat_SaveForNotifications
    case .increaseSpeed:
        return strings.Conversation_IncreaseSpeed
    case .sendGift:
        return strings.Conversation_ContextMenuSendAnotherGift
    case .sendScheduledNow:
        return strings.ScheduledMessages_SendNow
    case .editScheduledTime:
        return strings.ScheduledMessages_EditTime
    case .copy:
        return strings.Conversation_ContextMenuCopy
    case .translate:
        return strings.Conversation_ContextMenuTranslate
    case .speak:
        return strings.Conversation_ContextMenuSpeak
    case .saveToFiles:
        return strings.Conversation_SaveToFiles
    case .edit:
        return strings.Conversation_MessageDialogEdit
    case .editSuggestedPostMessage:
        return strings.Chat_ContextMenu_SuggestedPost_EditMessage
    case .editSuggestedPostTime:
        return strings.Chat_ContextMenu_SuggestedPost_EditTime
    case .editSuggestedPostPrice:
        return strings.Chat_ContextMenu_SuggestedPost_EditPrice
    case .createSuggestedPost:
        return strings.Chat_ContextMenu_SuggestedPost_Create
    case .unvotePoll:
        return strings.Conversation_UnvotePoll
    case .addTodoTask:
        return strings.Chat_Todo_ContextMenu_AddTask
    case .unpin:
        return strings.Conversation_Unpin
    case .copyLink:
        return strings.Conversation_ContextMenuCopyLink
    case .saveGif:
        return strings.Conversation_SaveGif
    case .editSticker:
        return strings.Stickers_EditSticker
    case .viewStickerPack:
        return strings.StickerPack_ViewPack
    case .forward:
        return strings.Conversation_ContextMenuForward
    case .activateLink:
        return strings.Username_ActivateAlertShow
    case .block:
        return strings.Conversation_ContextMenuBlock
    case .viewStats:
        return strings.Conversation_ContextViewStats
    case .viewPollStats:
        return strings.Conversation_ViewPollStats
    case .viewInChannel:
        return strings.Conversation_ViewInChannel
    case .select:
        return strings.Conversation_ContextMenuSelect
    case .delete:
        return strings.Conversation_ContextMenuDelete
    case .saveStickerToCameraRoll:
        return "ContextMenu.saveStickerToCameraRoll".i18n(lang)
    case .sendMoney:
        return "ContextMenu.sendMoney".i18n(lang)
    case .sendLogs:
        return "ContextMenu.sendLogs".i18n(lang)
    case .stopPoll:
        return "ContextMenu.stopPoll".i18n(lang)
    case .factCheck:
        return "ContextMenu.factCheck".i18n(lang)
    case .selectAll:
        return "ContextMenu.selectAll".i18n(lang)
    case .importSettings:
        return "ContextMenu.importSettings".i18n(lang)
    case .addFilter:
        return "MessageFilter.AddToFilter".i18n(lang)
    case .retry:
        return strings.Conversation_MessageDialogRetry
    case .json:
        return "JSON"
    case .editHistory:
        return "EditHistory.Title".i18n(lang)
    case .bookmark:
        return "Bookmarks.Add".i18n(lang)
    case .summarize:
        return "Summary.Action".i18n(lang)
    case .messageScreenshot:
        return "MessageScreenshot.Action".i18n(lang)
    }
}

private func rgContextMenuOrderEntries(presentationData: PresentationData, order: [RGContextMenuItemId], available: Set<RGContextMenuItemId>) -> [RGContextMenuOrderEntry] {
    var entries: [RGContextMenuOrderEntry] = []
    var index = 0
    for id in order where available.contains(id) {
        entries.append(.item(sortIndex: index, id: id, title: rgContextMenuItemTitle(id, strings: presentationData.strings), value: RGSimpleSettings.shared.contextMenuItemIsEnabled(id)))
        index += 1
    }
    entries.append(.info(sortIndex: index, text: i18n("Settings.ContextMenu.Notice", presentationData.strings.rgLanguageCode)))
    return entries
}

public func rgContextMenuOrderController(context: AccountContext) -> ViewController {
    let availableItems = RGSimpleSettings.shared.availableContextMenuItems(accountPeerId: context.account.peerId.toInt64())
    // Drives a rebuild after a toggle or a drag. The order lives in UserDefaults rather than in
    // controller state so that the context menu — built in a completely different module — reads the
    // same value without any plumbing.
    let statePromise = ValuePromise<[RGContextMenuItemId]>(RGSimpleSettings.shared.contextMenuOrder, ignoreRepeated: false)

    let arguments = RGContextMenuOrderArguments(setValue: { id, value in
        RGSimpleSettings.shared.setContextMenuItemIsEnabled(id, value)
        statePromise.set(RGSimpleSettings.shared.contextMenuOrder)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, order -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Settings.ContextMenu", presentationData.strings.rgLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: rgContextMenuOrderEntries(presentationData: presentationData, order: order, available: availableItems), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    // Every row is a drag handle, so a plain pan has to keep scrolling the list.
    controller.setReorderingRequiresLongPress(true)
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [RGContextMenuOrderEntry]) -> Signal<Bool, NoError> in
        var ids: [RGContextMenuItemId] = []
        for entry in entries {
            if case let .item(_, id, _, _) = entry {
                ids.append(id)
            }
        }
        guard fromIndex >= 0, fromIndex < ids.count, toIndex >= 0, toIndex < ids.count else {
            // The info row is in `entries` but not in `ids`, so a drop past the last item lands out
            // of range. Refusing is correct: the list snaps back rather than reordering wrongly.
            return .single(false)
        }
        let id = ids.remove(at: fromIndex)
        ids.insert(id, at: toIndex)
        RGSimpleSettings.shared.reorderVisibleContextMenuItems(ids)
        statePromise.set(RGSimpleSettings.shared.contextMenuOrder)
        return .single(true)
    })
    return controller
}

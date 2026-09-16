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
    let lang = strings.baseLanguageCode
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
        return strings.Conversation_SaveToFiles
    case .messageReplies:
        return strings.Conversation_ContextViewThread
    case .json:
        return "JSON"
    }
}

private func rgContextMenuOrderEntries(presentationData: PresentationData, order: [RGContextMenuItemId]) -> [RGContextMenuOrderEntry] {
    var entries: [RGContextMenuOrderEntry] = []
    var index = 0
    for id in order {
        entries.append(.item(sortIndex: index, id: id, title: rgContextMenuItemTitle(id, strings: presentationData.strings), value: RGSimpleSettings.shared.contextMenuItemIsEnabled(id)))
        index += 1
    }
    entries.append(.info(sortIndex: index, text: i18n("Settings.ContextMenu.Notice", presentationData.strings.baseLanguageCode)))
    return entries
}

public func rgContextMenuOrderController(context: AccountContext) -> ViewController {
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
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Settings.ContextMenu", presentationData.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: rgContextMenuOrderEntries(presentationData: presentationData, order: order), style: .blocks)
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
        RGSimpleSettings.shared.contextMenuOrder = ids
        statePromise.set(RGSimpleSettings.shared.contextMenuOrder)
        return .single(true)
    })
    return controller
}

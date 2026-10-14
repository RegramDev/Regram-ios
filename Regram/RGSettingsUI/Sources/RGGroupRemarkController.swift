// MARK: Regram
import AccountContext
import Display
import Foundation
import ItemListUI
import LocalizedPeerData
import PresentationDataUtils
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

private final class RGGroupRemarkArguments {
    let update: (String) -> Void
    let save: () -> Void
    init(update: @escaping (String) -> Void, save: @escaping () -> Void) {
        self.update = update
        self.save = save
    }
}

private enum RGGroupRemarkEntry: ItemListNodeEntry {
    case originalName(String)
    case input(text: String, placeholder: String)
    case notice(String)
    case clear(String)

    var stableId: Int32 {
        switch self { case .originalName: return 0; case .input: return 1; case .notice: return 2; case .clear: return 3 }
    }
    var section: ItemListSectionId { if case .clear = self { return 1 }; return 0 }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGGroupRemarkArguments
        switch self {
        case let .originalName(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .input(text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: text, placeholder: placeholder, type: .regular(capitalization: true, autocorrection: false), returnKeyType: .done, clearType: .onFocus, maxLength: RGGroupRemarks.maximumLength, sectionId: section, textUpdated: arguments.update, action: arguments.save)
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .clear(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: { arguments.update("") })
        }
    }
}

public func rgGroupRemarkController(context: AccountContext, peer: EnginePeer) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let initialText = RGGroupRemarks.shared.name(accountId: accountId, peerId: peer.id.toInt64()) ?? ""
    let text = Atomic(value: initialText)
    let state = ValuePromise(initialText, ignoreRepeated: true)
    weak var currentController: ItemListController?
    let arguments = RGGroupRemarkArguments(update: { value in
        _ = text.swap(value)
        state.set(value)
    }, save: {
        guard peer.rgCanSetGroupRemark else { return }
        RGGroupRemarks.shared.setName(text.with { $0 }, accountId: accountId, peerId: peer.id.toInt64())
        currentController?.view.endEditing(true)
        _ = (currentController?.navigationController as? NavigationController)?.popViewController(animated: true)
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, state.get())
    |> map { presentationData, value -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.rgLanguageCode
        let originalName = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        let entries: [RGGroupRemarkEntry] = [
            .originalName(String(format: "GroupRemark.OriginalName".i18n(lang), originalName)),
            .input(text: value, placeholder: originalName),
            .notice("GroupRemark.Notice".i18n(lang)),
            .clear("GroupRemark.UseOriginalName".i18n(lang))
        ]
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("GroupRemark.Title".i18n(lang)), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Save), style: .bold, enabled: peer.rgCanSetGroupRemark, action: arguments.save), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    currentController = controller
    return controller
}

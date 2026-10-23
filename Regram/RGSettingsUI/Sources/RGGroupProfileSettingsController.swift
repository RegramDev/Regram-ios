// MARK: Regram — adapted from NextAlone/Nagram-iOS (fa29656a2427); original contributors retain copyright.
import AccountContext
import Display
import ItemListUI
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramPresentationData

private final class RGFeatureGroupProfileSettingsArguments {
    let update: (RGFeatureGroupProfileSettingItem, Bool) -> Void

    init(update: @escaping (RGFeatureGroupProfileSettingItem, Bool) -> Void) {
        self.update = update
    }
}

private enum RGFeatureGroupProfileSettingsEntryStableId: Hashable {
    case item(RGFeatureGroupProfileSettingItem)
    case footer
}

private enum RGFeatureGroupProfileSettingsEntry: ItemListNodeEntry {
    case item(RGFeatureGroupProfileSettingItem, String, Bool)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: RGFeatureGroupProfileSettingsEntryStableId {
        switch self {
        case let .item(item, _, _):
            return .item(item)
        case .footer:
            return .footer
        }
    }

    static func ==(lhs: RGFeatureGroupProfileSettingsEntry, rhs: RGFeatureGroupProfileSettingsEntry) -> Bool {
        switch lhs {
        case let .item(lhsItem, lhsTitle, lhsValue):
            if case let .item(rhsItem, rhsTitle, rhsValue) = rhs {
                return lhsItem == rhsItem && lhsTitle == rhsTitle && lhsValue == rhsValue
            }
            return false
        case let .footer(lhsText):
            if case let .footer(rhsText) = rhs {
                return lhsText == rhsText
            }
            return false
        }
    }

    static func <(lhs: RGFeatureGroupProfileSettingsEntry, rhs: RGFeatureGroupProfileSettingsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case let .item(item, _, _):
            return RGFeatureGroupProfileSettingItem.allCases.firstIndex(of: item) ?? 0
        case .footer:
            return RGFeatureGroupProfileSettingItem.allCases.count
        }
    }

    var tag: ItemListItemTag? {
        if case let .item(item, _, _) = self {
            return RGSimpleSettingsFocusTag(item.rawValue)
        }
        return nil
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGFeatureGroupProfileSettingsArguments
        switch self {
        case let .item(item, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(item, value)
            }, tag: self.tag)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func rgFeatureGroupProfileSettingsController(context: AccountContext, focusOnRow: String? = nil) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    let arguments = RGFeatureGroupProfileSettingsArguments(update: { item, visible in
        RGSimpleSettings.shared.setGroupProfileSettingItemVisible(item, visible: visible)
        bump()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries = RGFeatureGroupProfileSettingItem.allCases.map { item in
            RGFeatureGroupProfileSettingsEntry.item(
                item,
                rgFeatureI18n("features.GroupProfileSettings.Item.\(item.rawValue)", lang),
                RGSimpleSettings.shared.isGroupProfileSettingItemVisible(item)
            )
        }
        entries.append(.footer(rgFeatureI18n("features.GroupProfileSettings.Footer", lang)))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(rgFeatureI18n("features.GroupProfileSettings", lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            initialScrollToItem: rgFeatureFocusScrollToItem(entries: entries, focusOnRow: focusOnRow),
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    rgFeatureHighlightFocusedRow(controller: controller, focusOnRow: focusOnRow)
    return controller
}

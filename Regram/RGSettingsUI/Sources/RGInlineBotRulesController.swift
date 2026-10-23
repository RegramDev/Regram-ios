// MARK: Regram — automatic inline queries and readable rule inspection share one page.
import Foundation
import AccountContext
import Display
import ItemListUI
import RGLinkMetadata
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramPresentationData

private final class RGFeatureInlineBotRulesArguments {
    let setEnabled: (Bool) -> Void
    init(setEnabled: @escaping (Bool) -> Void) {
        self.setEnabled = setEnabled
    }
}

private enum RGFeatureInlineBotRulesEntry: ItemListNodeEntry {
    case header(String)
    case enabled(String, Bool)
    case notice(String)
    case rulesHeader(String)
    case ruleHeader(Int, String)
    case rule(Int, String)
    case footer(Int, String)

    var section: ItemListSectionId {
        switch self {
        case .header, .enabled, .notice: return 0
        case .rulesHeader: return 1
        case let .ruleHeader(index, _), let .rule(index, _): return Int32(index + 1)
        case let .footer(count, _): return Int32(max(1, count))
        }
    }
    var stableId: Int {
        switch self {
        case .header: return 0
        case .enabled: return 1
        case .notice: return 2
        case .rulesHeader: return 3
        case let .ruleHeader(index, _): return 4 + index * 2
        case let .rule(index, _): return 5 + index * 2
        case let .footer(count, _): return 4 + count * 2
        }
    }
    var tag: ItemListItemTag? {
        if case .enabled = self { return RGSimpleSettingsFocusTag("enabled") }
        return nil
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGFeatureInlineBotRulesArguments
        switch self {
        case let .header(title), let .rulesHeader(title), let .ruleHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .enabled(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.setEnabled, tag: self.tag)
        case let .rule(_, patterns):
            // Rules are read-only. Give long expressions the full card width and wrap them naturally.
            return ItemListMultilineTextItem(presentationData: presentationData, text: patterns, enabledEntityTypes: [], font: .monospace, sectionId: self.section, style: .blocks)
        case let .notice(text), let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func rgFeatureInlineBotRulesController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    RGLinkMetadata.shared.refreshIfNeeded(engine: context.engine)
    let enabled = ValuePromise<Bool>(RGSimpleSettings.shared.autoInlineBotEnabled, ignoreRepeated: true)
    let arguments = RGFeatureInlineBotRulesArguments(setEnabled: { value in
        RGSimpleSettings.shared.autoInlineBotEnabled = value
        enabled.set(value)
    })
    // Refresh the open list after metadata arrives, rather than waiting for a theme/language change.
    let rules = Signal<[RGInlineBotRule], NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RGLinkPreviewRules.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(RGLinkMetadata.shared.currentInlineBotRules())
        }
        subscriber.putNext(RGLinkMetadata.shared.currentInlineBotRules())
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, enabled.get(), rules |> distinctUntilChanged)
    |> map { presentationData, isEnabled, rules -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [RGFeatureInlineBotRulesEntry] = [
            .header(rgFeatureI18n("features.InlineBots.Title", lang)),
            .enabled(rgFeatureI18n("features.AutoInlineBot.Enabled", lang), isEnabled),
            .notice(rgFeatureI18n("features.AutoInlineBot.Footer", lang)),
            .rulesHeader(rgFeatureI18n("features.InlineBotRules", lang))
        ]
        for (index, rule) in rules.enumerated() {
            entries.append(.ruleHeader(index, "@\(rule.username)"))
            entries.append(.rule(index, rule.rules.joined(separator: "\n\n")))
        }
        entries.append(.footer(rules.count, rgFeatureI18n("features.InlineBotRules.Footer", lang)))
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(rgFeatureI18n("features.InlineBots.Title", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: rgFeatureFocusScrollToItem(entries: entries, focusOnRow: focusSetting), animateChanges: false), arguments)
        )
    }
    let controller = ItemListController(context: context, state: signal)
    rgFeatureHighlightFocusedRow(controller: controller, focusOnRow: focusSetting)
    return controller
}

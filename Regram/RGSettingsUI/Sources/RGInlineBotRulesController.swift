// MARK: Regram — rule inspection uses the same link manager as automatic queries.
import AccountContext
import Display
import ItemListUI
import RGLinkMetadata
import RGStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData

private final class RGFeatureInlineBotRulesArguments {
}

private enum RGFeatureInlineBotRulesEntry: ItemListNodeEntry {
    case rule(Int, String, String)
    case footer(Int, String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int { switch self { case let .rule(index, _, _): return index; case let .footer(index, _): return index } }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .rule(_, username, patterns):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "@\(username)", label: patterns, sectionId: self.section, style: .blocks, action: nil)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func rgFeatureInlineBotRulesController(context: AccountContext) -> ViewController {
    RGLinkMetadata.shared.refreshIfNeeded(engine: context.engine)
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [RGFeatureInlineBotRulesEntry] = []
        for (index, rule) in RGLinkMetadata.shared.currentInlineBotRules().enumerated() {
            entries.append(.rule(index, rule.username, rule.rules.joined(separator: "\n")))
        }
        entries.append(.footer(entries.count, rgFeatureI18n("features.InlineBotRules.Footer", lang)))
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(rgFeatureI18n("features.InlineBotRules", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), RGFeatureInlineBotRulesArguments())
        )
    }
    return ItemListController(context: context, state: signal)
}

// MARK: Regram — layout settings for the upstream Telegram tab bar.
import AccountContext
import AsyncDisplayKit
import ComponentFlow
import Display
import Foundation
import ItemListUI
import RGItemListUI
import RGSimpleSettings
import RGStrings
import RGSwiftUI
import PresentationDataUtils
import SwiftSignalKit
import SearchBarNode // MARK: Regram
import TabBarComponent
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData
import UIKit

private final class RGBottomBarArguments {
    let update: ((inout RGBottomBarSettings) -> Void) -> Void
    let reset: () -> Void

    init(update: @escaping ((inout RGBottomBarSettings) -> Void) -> Void, reset: @escaping () -> Void) {
        self.update = update
        self.reset = reset
    }
}

private enum RGBottomBarSwitchOption: Int32 {
    case hidden
    case topSearch
    case labels
    case automaticWidth
}

private enum RGBottomBarEntry: ItemListNodeEntry {
    case preview(section: Int32, settings: RGBottomBarSettings, strings: PresentationStrings, itemTitles: [RGBottomBarItemId: String], topSearchTitle: String, topSearchVisibleHint: String, topSearchHiddenHint: String, bottomBarTitle: String, emptyBottomTitle: String)
    case header(stableId: Int32, section: Int32, text: String)
    case toggle(stableId: Int32, section: Int32, title: String, value: Bool, option: RGBottomBarSwitchOption)
    case visibility(stableId: Int32, section: Int32, title: String, settings: RGBottomBarSettings, itemTitles: [RGBottomBarItemId: String])
    case slider(stableId: Int32, section: Int32, title: String, value: Int32)
    case reset(stableId: Int32, section: Int32, title: String)
    case footer(stableId: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .preview(section, _, _, _, _, _, _, _, _):
            return section
        case let .header(_, section, _):
            return section
        case let .toggle(_, section, _, _, _):
            return section
        case let .visibility(_, section, _, _, _):
            return section
        case let .slider(_, section, _, _):
            return section
        case let .reset(_, section, _):
            return section
        case let .footer(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case .preview:
            return 0
        case let .header(stableId, _, _):
            return stableId
        case let .toggle(stableId, _, _, _, _):
            return stableId
        case let .visibility(stableId, _, _, _, _):
            return stableId
        case let .slider(stableId, _, _, _):
            return stableId
        case let .reset(stableId, _, _):
            return stableId
        case let .footer(stableId, _, _):
            return stableId
        }
    }

    static func ==(lhs: RGBottomBarEntry, rhs: RGBottomBarEntry) -> Bool {
        switch lhs {
        case let .preview(lSection, lSettings, lStrings, lItemTitles, lTopSearchTitle, lTopSearchVisibleHint, lTopSearchHiddenHint, lBottomBarTitle, lEmptyBottomTitle):
            if case let .preview(rSection, rSettings, rStrings, rItemTitles, rTopSearchTitle, rTopSearchVisibleHint, rTopSearchHiddenHint, rBottomBarTitle, rEmptyBottomTitle) = rhs {
                return lSection == rSection && lSettings == rSettings && lStrings.rgLanguageCode == rStrings.rgLanguageCode && lItemTitles == rItemTitles && lTopSearchTitle == rTopSearchTitle && lTopSearchVisibleHint == rTopSearchVisibleHint && lTopSearchHiddenHint == rTopSearchHiddenHint && lBottomBarTitle == rBottomBarTitle && lEmptyBottomTitle == rEmptyBottomTitle
            }
            return false
        case let .header(lId, lSection, lText):
            if case let .header(rId, rSection, rText) = rhs {
                return lId == rId && lSection == rSection && lText == rText
            }
            return false
        case let .toggle(lId, lSection, lTitle, lValue, lOption):
            if case let .toggle(rId, rSection, rTitle, rValue, rOption) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue && lOption == rOption
            }
            return false
        case let .visibility(lId, lSection, lTitle, lSettings, lItemTitles):
            if case let .visibility(rId, rSection, rTitle, rSettings, rItemTitles) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lSettings == rSettings && lItemTitles == rItemTitles
            }
            return false
        case let .slider(lId, lSection, lTitle, lValue):
            if case let .slider(rId, rSection, rTitle, rValue) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue
            }
            return false
        case let .reset(lId, lSection, lTitle):
            if case let .reset(rId, rSection, rTitle) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle
            }
            return false
        case let .footer(lId, lSection, lText):
            if case let .footer(rId, rSection, rText) = rhs {
                return lId == rId && lSection == rSection && lText == rText
            }
            return false
        }
    }

    static func <(lhs: RGBottomBarEntry, rhs: RGBottomBarEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    var settingsIdentifier: String? {
        switch self {
        case let .toggle(_, _, _, _, option): return String(describing: option)
        case .visibility: return "visibility"
        case .slider: return "width"
        case .reset: return "reset"
        default: return nil
        }
    }
    var tag: ItemListItemTag? { settingsIdentifier.map(RGSettingsItemTag.init) }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        return rgSettingsLinkItem(baseItem(presentationData: presentationData, arguments: arguments), destination: settingsIdentifier.flatMap { RGSettingsDestination(page: "bottomBar", item: $0) })
    }
    private func baseItem(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGBottomBarArguments
        switch self {
        case let .preview(_, settings, strings, itemTitles, topSearchTitle, topSearchVisibleHint, topSearchHiddenHint, bottomBarTitle, emptyBottomTitle):
            return RGBottomBarPreviewItem(
                theme: presentationData.theme,
                settings: settings,
                strings: strings,
                itemTitles: itemTitles,
                topSearchTitle: topSearchTitle,
                topSearchVisibleHint: topSearchVisibleHint,
                topSearchHiddenHint: topSearchHiddenHint,
                bottomBarTitle: bottomBarTitle,
                emptyBottomTitle: emptyBottomTitle,
                sectionId: self.section,
                update: arguments.update
            )
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, title, value, option):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                arguments.update { settings in
                    switch option {
                    case .hidden: settings.isBottomBarVisible = !value
                    case .topSearch:
                        settings.topSearchVisible = value
                    case .automaticWidth:
                        settings.automaticWidth = value
                        if !value { settings.buttonWidthFillRatio = max(50, settings.buttonWidthFillRatio) }
                    case .labels:
                        settings.showLabels = value
                    }
                }
            }, tag: self.tag)
        case let .visibility(_, section, title, settings, itemTitles):
            let chips = RGBottomBarItemId.allCases.map { id in
                let isSelected = settings.isVisible(id)
                let isEnabled = settings.canHide(id)
                return RGBottomBarChipRowItem.Chip(id: id.rawValue, title: itemTitles[id] ?? id.rawValue, isSelected: isSelected, isEnabled: isEnabled)
            }
            return RGBottomBarChipRowItem(presentationData: presentationData, title: title, chips: chips, sectionId: section, selected: { rawValue in
                guard let id = RGBottomBarItemId(rawValue: rawValue) else {
                    return
                }
                arguments.update { settings in
                    if id == .search {
                        settings.toggleHidden(.search)
                    } else {
                        if settings.isVisible(id) {
                            settings.hide(id)
                        } else {
                            settings.moveToBottom(id, at: settings.bottomItems.count)
                        }
                    }
                }
            })
        case let .slider(_, section, title, value):
            return RGSliderItem(theme: presentationData.theme, minValue: 50, maxValue: 100, value: value, title: title, sectionId: section, updated: { value in
                arguments.update { settings in
                    settings.buttonWidthFillRatio = value
                    settings.widthMode = value >= 100 ? .full : .adaptive
                    settings.slotMode = value <= 0 ? .preserveHidden : .visibleOnly
                }
            }, tag: self.tag)
        case let .reset(_, section, title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: {
                arguments.reset()
            }, tag: self.tag)
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func rgBottomBarSettings(_ settings: RGBottomBarSettings, applyingShowCallsTab showCallsTab: Bool, showContactsTab: Bool) -> RGBottomBarSettings {
    var result = settings
    result.setVisible(.calls, visible: showCallsTab)
    result.setVisible(.contacts, visible: showContactsTab)
    return result
}

public func rgBottomBarSettingsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var currentShowContactsTab = CallListSettings.defaultSettings.showContactsTab
    var currentShowCallsTab = CallListSettings.defaultSettings.showTab
    var pendingShowCallsTab: Bool?
    var pendingShowContactsTab: Bool?

    let saveSettings: (RGBottomBarSettings) -> Void = { settings in
        let normalizedSettings = settings
        let nextShowContactsTab = normalizedSettings.isVisible(.contacts)
        if nextShowContactsTab != currentShowContactsTab {
            currentShowContactsTab = nextShowContactsTab
            pendingShowContactsTab = nextShowContactsTab
            let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowContactsTab(nextShowContactsTab) }).startStandalone()
        }
        let nextShowCallsTab = normalizedSettings.isVisible(.calls)
        RGSimpleSettings.shared.bottomBarSettings = normalizedSettings
        if nextShowCallsTab != currentShowCallsTab {
            currentShowCallsTab = nextShowCallsTab
            pendingShowCallsTab = nextShowCallsTab
            let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, {
                $0.withUpdatedShowTab(nextShowCallsTab)
            }).startStandalone()
        }
    }

    let arguments = RGBottomBarArguments(update: { update in
        var settings = rgBottomBarSettings(RGSimpleSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab, showContactsTab: currentShowContactsTab)
        update(&settings)
        saveSettings(settings)
        bump()
    }, reset: {
        saveSettings(RGBottomBarSettings())
        bump()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get(),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> CallListSettings in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? .defaultSettings
        }
    )
    |> map { presentationData, _, callSettings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let showCallsTab = callSettings.showTab
        if let pending = pendingShowContactsTab {
            if callSettings.showContactsTab == pending { pendingShowContactsTab = nil }
            currentShowContactsTab = pending
        } else { currentShowContactsTab = callSettings.showContactsTab }
        if let pendingShowCallsTabValue = pendingShowCallsTab {
            if showCallsTab == pendingShowCallsTabValue {
                pendingShowCallsTab = nil
            }
            currentShowCallsTab = pendingShowCallsTabValue
        } else {
            currentShowCallsTab = showCallsTab
        }
        let lang = presentationData.strings.rgLanguageCode
        let settings = rgBottomBarSettings(RGSimpleSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab, showContactsTab: currentShowContactsTab)
        let itemTitles: [RGBottomBarItemId: String] = [
            .contacts: i18n("RG.BottomBarLayout.Item.contacts", lang),
            .calls: i18n("RG.BottomBarLayout.Item.calls", lang),
            .chats: i18n("RG.BottomBarLayout.Item.chats", lang),
            .settings: i18n("RG.BottomBarLayout.Item.settings", lang),
            .search: i18n("RG.BottomBarLayout.Item.search", lang)
        ]

        var entries: [RGBottomBarEntry] = [
            .preview(
                section: 0,
                settings: settings,
                strings: presentationData.strings,
                itemTitles: itemTitles,
                topSearchTitle: i18n("RG.BottomBarLayout.TopBar", lang),
                topSearchVisibleHint: i18n("RG.BottomBarLayout.TopSearchHint.visible", lang),
                topSearchHiddenHint: i18n("RG.BottomBarLayout.TopSearchHint.hidden", lang),
                bottomBarTitle: i18n("RG.BottomBarLayout.BottomBar", lang),
                emptyBottomTitle: i18n("RG.BottomBarLayout.EmptyBottom", lang)
            ),
            .header(stableId: 1, section: 1, text: i18n("RG.BottomBarLayout.State", lang)),
            .toggle(stableId: 2, section: 1, title: i18n("Settings.Tabs.HideTabBar", lang), value: !settings.isBottomBarVisible, option: .hidden),
            .toggle(stableId: 3, section: 1, title: i18n("RG.BottomBarLayout.TopSearch", lang), value: settings.topSearchVisible, option: .topSearch),
            .visibility(stableId: 5, section: 1, title: i18n("RG.BottomBarLayout.Visibility", lang), settings: settings, itemTitles: itemTitles),
            .header(stableId: 6, section: 2, text: i18n("RG.BottomBarLayout.Options", lang)),
            .toggle(stableId: 7, section: 2, title: i18n("Settings.Tabs.Width.Automatic", lang), value: settings.automaticWidth, option: .automaticWidth),
            .toggle(stableId: 8, section: 2, title: i18n("RG.BottomBarLayout.ShowLabels", lang), value: settings.showLabels, option: .labels),
            .reset(stableId: 10, section: 3, title: i18n("RG.BottomBarLayout.Reset", lang)),
            .footer(stableId: 11, section: 3, text: i18n("RG.BottomBarLayout.Footer", lang))
        ]

        if !settings.automaticWidth {
            entries.insert(.slider(stableId: 9, section: 2, title: i18n("RG.BottomBarLayout.Width", lang), value: settings.buttonWidthFillRatio), at: entries.count - 2)
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("RG.BottomBarLayout", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: rgSettingsScrollTarget(entries, item: focusSetting == "bottomSearch" || focusSetting == "searchMode" ? "visibility" : focusSetting == "width" && settings.automaticWidth ? "automaticWidth" : focusSetting), animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = RGSettingsListController(context: context, state: signal)
    controller.navigationPresentation = .default
    return controller
}

private final class RGBottomBarChipRowItem: ListViewItem, ItemListItem {
    struct Chip: Equatable {
        let id: String
        let title: String
        let isSelected: Bool
        let isEnabled: Bool
    }

    let presentationData: ItemListPresentationData
    var theme: PresentationTheme {
        return self.presentationData.theme
    }
    let title: String
    let chips: [Chip]
    let sectionId: ItemListSectionId
    let selected: (String) -> Void

    init(presentationData: ItemListPresentationData, title: String, chips: [Chip], sectionId: ItemListSectionId, selected: @escaping (String) -> Void) {
        self.presentationData = presentationData
        self.title = title
        self.chips = chips
        self.sectionId = sectionId
        self.selected = selected
    }

    var selectable: Bool {
        return false
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = RGBottomBarChipRowItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? RGBottomBarChipRowItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class RGBottomBarChipButton: UIButton {
    var chipId: String?
    override func layoutSubviews() {
        super.layoutSubviews()
        self.titleLabel?.frame = self.bounds.insetBy(dx: 6.0, dy: 10.0)
    }
}

private final class RGBottomBarChipRowItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode = ASDisplayNode()
    private let topStripeNode = ASDisplayNode()
    private let bottomStripeNode = ASDisplayNode()
    private let maskNode = ASImageNode()
    private let titleLabel = UILabel()
    private var buttons: [String: RGBottomBarChipButton] = [:]
    private var item: RGBottomBarChipRowItem?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        self.backgroundNode.isLayerBacked = true
        super.init(layerBacked: false)
        self.addSubnode(self.backgroundNode)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.titleLabel)
    }

    func asyncLayout() -> (_ item: RGBottomBarChipRowItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = 16.0
            let leftInset = params.leftInset + 16.0
            let availableWidth = max(1.0, params.width - params.leftInset - params.rightInset - 32.0)
            let baseFontSize = item.presentationData.fontSize.itemListBaseFontSize
            let titleFont = Font.regular(baseFontSize)
            let chipFont = Font.medium(floor(baseFontSize * 13.0 / 17.0))
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            let titleBounds = (item.title as NSString).boundingRect(with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: titleFont, .paragraphStyle: paragraphStyle], context: nil)
            let titleFrame = CGRect(x: leftInset, y: 12.0, width: availableWidth, height: ceil(max(titleFont.lineHeight, titleBounds.height)))
            let chipCount = max(1, item.chips.count)
            let gap = min(7.0, max(0.0, (availableWidth - CGFloat(chipCount) * 48.0) / CGFloat(max(1, chipCount - 1))))
            let chipInsets = UIEdgeInsets(top: 10.0, left: 6.0, bottom: 10.0, right: 6.0)
            let naturalWidths = item.chips.map { max(1.0, ceil(($0.title as NSString).size(withAttributes: [.font: chipFont]).width)) }
            let totalNaturalWidth = max(1.0, naturalWidths.reduce(0.0, +))
            let totalChipWidth = max(1.0, availableWidth - gap * CGFloat(chipCount - 1))
            let minimumChipWidth = min(44.0, totalChipWidth / CGFloat(chipCount))
            let remainingWidth = max(0.0, totalChipWidth - minimumChipWidth * CGFloat(chipCount))
            let chipHeight = max(44.0, ceil(chipFont.lineHeight) + chipInsets.top + chipInsets.bottom)
            var chipFrames: [CGRect] = []
            var nextX: CGFloat = 0.0
            let rowY = titleFrame.maxY + 10.0
            for naturalWidth in naturalWidths {
                let chipWidth = minimumChipWidth + remainingWidth * naturalWidth / totalNaturalWidth
                chipFrames.append(CGRect(x: leftInset + nextX, y: rowY, width: chipWidth, height: chipHeight))
                nextX += chipWidth + gap
            }
            let contentHeight = rowY + (item.chips.isEmpty ? 0.0 : chipHeight) + 12.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: contentHeight), insets: itemListNeighborsGroupedInsets(neighbors, params))
            let insets = layout.insets
            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                self.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                self.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                self.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                if self.topStripeNode.supernode == nil {
                    self.insertSubnode(self.topStripeNode, aboveSubnode: self.backgroundNode)
                }
                if self.bottomStripeNode.supernode == nil {
                    self.insertSubnode(self.bottomStripeNode, aboveSubnode: self.backgroundNode)
                }
                if self.maskNode.supernode == nil {
                    self.insertSubnode(self.maskNode, aboveSubnode: self.bottomStripeNode)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    self.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    self.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    self.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    self.bottomStripeNode.isHidden = hasCorners
                }

                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentHeight + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentHeight + bottomStripeOffset), size: CGSize(width: params.width - params.rightInset - bottomStripeInset - separatorRightInset, height: separatorHeight))

                self.titleLabel.text = item.title
                self.titleLabel.font = titleFont
                self.titleLabel.numberOfLines = 0
                self.titleLabel.lineBreakMode = .byWordWrapping
                self.titleLabel.textColor = item.theme.list.itemPrimaryTextColor
                self.titleLabel.frame = titleFrame

                var activeIds = Set<String>()
                var accessibilityElements: [Any] = [self.titleLabel]
                for (index, chip) in item.chips.enumerated() {
                    activeIds.insert(chip.id)
                    let button = self.button(for: chip.id)
                    button.chipId = chip.id
                    button.frame = chipFrames[index]
                    button.titleLabel?.font = chipFont
                    self.configure(button: button, chip: chip, theme: item.theme)
                    accessibilityElements.append(button)
                }
                for (id, button) in self.buttons {
                    button.isHidden = !activeIds.contains(id)
                }
                self.view.accessibilityElements = accessibilityElements
            })
        }
    }

    private func button(for id: String) -> RGBottomBarChipButton {
        if let current = self.buttons[id] {
            return current
        }
        let button = RGBottomBarChipButton(type: .system)
        button.layer.cornerRadius = 15.0
        button.layer.borderWidth = UIScreenPixel
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.4
        button.titleLabel?.baselineAdjustment = .alignCenters
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchUpInside)
        self.view.addSubview(button)
        self.buttons[id] = button
        return button
    }

    private func configure(button: RGBottomBarChipButton, chip: RGBottomBarChipRowItem.Chip, theme: PresentationTheme) {
        button.setTitle(chip.title, for: .normal)
        button.isEnabled = chip.isEnabled
        button.isAccessibilityElement = true
        button.accessibilityLabel = chip.title
        var accessibilityTraits: UIAccessibilityTraits = [.button]
        if chip.isSelected {
            accessibilityTraits.insert(.selected)
        }
        if !chip.isEnabled {
            accessibilityTraits.insert(.notEnabled)
        }
        button.accessibilityTraits = accessibilityTraits
        if chip.isSelected {
            let selectedColor = theme.list.itemCheckColors.fillColor // MARK: Regram — paired theme colors stay legible.
            button.backgroundColor = selectedColor
            button.layer.borderColor = selectedColor.cgColor
            button.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
            button.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .disabled)
        } else {
            button.backgroundColor = theme.list.itemInputField.backgroundColor
            button.layer.borderColor = theme.list.itemBlocksSeparatorColor.cgColor
            button.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
            button.setTitleColor(theme.list.itemSecondaryTextColor, for: .disabled)
        }
        button.alpha = chip.isEnabled ? 1.0 : 0.75
    }

    @objc private func buttonPressed(_ button: RGBottomBarChipButton) {
        guard button.isEnabled, let chipId = button.chipId, let item = self.item, item.chips.contains(where: { $0.id == chipId && $0.isEnabled }) else {
            return
        }
        item.selected(chipId)
    }
}

private final class RGBottomBarPreviewItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let settings: RGBottomBarSettings
    let strings: PresentationStrings
    let itemTitles: [RGBottomBarItemId: String]
    let topSearchTitle: String
    let topSearchVisibleHint: String
    let topSearchHiddenHint: String
    let bottomBarTitle: String
    let emptyBottomTitle: String
    let sectionId: ItemListSectionId
    let update: ((inout RGBottomBarSettings) -> Void) -> Void

    init(theme: PresentationTheme, settings: RGBottomBarSettings, strings: PresentationStrings, itemTitles: [RGBottomBarItemId: String], topSearchTitle: String, topSearchVisibleHint: String, topSearchHiddenHint: String, bottomBarTitle: String, emptyBottomTitle: String, sectionId: ItemListSectionId, update: @escaping ((inout RGBottomBarSettings) -> Void) -> Void) {
        self.theme = theme
        self.settings = settings
        self.strings = strings
        self.itemTitles = itemTitles
        self.topSearchTitle = topSearchTitle
        self.topSearchVisibleHint = topSearchVisibleHint
        self.topSearchHiddenHint = topSearchHiddenHint
        self.bottomBarTitle = bottomBarTitle
        self.emptyBottomTitle = emptyBottomTitle
        self.sectionId = sectionId
        self.update = update
    }

    var selectable: Bool {
        return false
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = RGBottomBarPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? RGBottomBarPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class RGBottomBarPreviewItemNode: ListViewItemNode, ItemListItemNode, UIGestureRecognizerDelegate {
    private var item: RGBottomBarPreviewItem?
    private let topSearchTitleLabel = UILabel()
    private let topSearchHintLabel = UILabel()
    private let bottomBarTitleLabel = UILabel()
    private let emptyBottomLabel = UILabel()
    private let backgroundView = UIView()
    private let topSearchView = UIView()
    private var topSearchNode: SearchBarNode?
    private let tabBarComponentView = ComponentView<Empty>()
    private let externalDropView = UIView()
    private var itemFrames: [RGBottomBarItemId: CGRect] = [:]
    private var componentIdsByItemId: [RGBottomBarItemId: AnyHashable] = [:]
    private var itemIdsByComponentId: [AnyHashable: RGBottomBarItemId] = [:]
    private var bottomFrame: CGRect = .zero
    private var externalFrame: CGRect = .zero
    private var draggingItem: RGBottomBarItemId?
    private var panGestureRecognizer: UIPanGestureRecognizer?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.backgroundView)
        self.backgroundView.addSubview(self.topSearchTitleLabel)
        self.backgroundView.addSubview(self.topSearchView)
        self.backgroundView.addSubview(self.topSearchHintLabel)
        self.backgroundView.addSubview(self.bottomBarTitleLabel)
        self.backgroundView.addSubview(self.emptyBottomLabel)
        self.backgroundView.addSubview(self.externalDropView)

        self.topSearchView.isUserInteractionEnabled = false

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        self.backgroundView.addGestureRecognizer(panGesture)
        self.panGestureRecognizer = panGesture
    }

    func asyncLayout() -> (_ item: RGBottomBarPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let height: CGFloat = 228.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                self.backgroundColor = item.theme.list.blocksBackgroundColor
                self.configure(theme: item.theme, params: params, height: height)
            })
        }
    }

    private func configure(theme: PresentationTheme, params: ListViewItemLayoutParams, height: CGFloat) {
        guard let item = self.item else {
            return
        }

        let controlLeftInset = params.leftInset + 16.0
        let controlRightInset = params.rightInset + 16.0
        let controlWidth = params.width - controlLeftInset - controlRightInset

        self.backgroundView.frame = CGRect(x: 0.0, y: 8.0, width: params.width, height: height - 16.0)
        self.backgroundView.backgroundColor = .clear
        self.backgroundView.layer.cornerRadius = 0.0
        self.backgroundView.clipsToBounds = false

        self.topSearchTitleLabel.frame = CGRect(x: controlLeftInset, y: 14.0, width: controlWidth, height: 18.0)
        self.topSearchTitleLabel.text = item.topSearchTitle
        self.topSearchTitleLabel.font = Font.regular(11.0)
        self.topSearchTitleLabel.textColor = theme.list.itemSecondaryTextColor

        let topSearchFrame = CGRect(x: controlLeftInset, y: 36.0, width: controlWidth, height: 42.0)
        self.topSearchView.frame = topSearchFrame
        // MARK: Regram — the preview uses the same search field as the upstream chat header.
        let searchTheme = SearchBarNodeTheme(theme: theme, hasBackground: false, hasSeparator: false, inline: true)
        let searchNode: SearchBarNode
        if let current = self.topSearchNode { searchNode = current; searchNode.updateThemeAndStrings(theme: searchTheme, presentationTheme: theme, strings: item.strings) }
        else {
            searchNode = SearchBarNode(theme: searchTheme, presentationTheme: theme, strings: item.strings, fieldStyle: .inlineNavigation, displayBackground: false)
            self.topSearchNode = searchNode; self.topSearchView.addSubview(searchNode.view)
        }
        searchNode.placeholderString = NSAttributedString(string: item.strings.Common_Search, font: Font.regular(17), textColor: searchTheme.placeholder)
        searchNode.frame = CGRect(origin: .zero, size: topSearchFrame.size)
        searchNode.updateLayout(boundingSize: topSearchFrame.size, leftInset: 0, rightInset: 0, transition: .immediate)
        self.topSearchView.alpha = item.settings.topSearchVisible ? 1.0 : 0.35

        self.topSearchHintLabel.frame = CGRect(x: controlLeftInset, y: 80.0, width: controlWidth, height: 16.0)
        self.topSearchHintLabel.text = item.settings.topSearchVisible ? item.topSearchVisibleHint : item.topSearchHiddenHint
        self.topSearchHintLabel.font = Font.regular(10.0)
        self.topSearchHintLabel.textColor = item.settings.topSearchVisible ? theme.list.itemSecondaryTextColor : theme.list.itemDisabledTextColor

        self.bottomBarTitleLabel.frame = CGRect(x: controlLeftInset, y: 104.0, width: controlWidth, height: 18.0)
        self.bottomBarTitleLabel.text = item.bottomBarTitle
        self.bottomBarTitleLabel.font = Font.regular(11.0)
        self.bottomBarTitleLabel.textColor = theme.list.itemSecondaryTextColor

        self.emptyBottomLabel.text = item.emptyBottomTitle
        self.emptyBottomLabel.textAlignment = .center
        self.emptyBottomLabel.font = Font.regular(13.0)
        self.emptyBottomLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyBottomLabel.backgroundColor = theme.list.itemInputField.backgroundColor
        self.emptyBottomLabel.layer.cornerRadius = 16.0
        self.emptyBottomLabel.layer.masksToBounds = true

        self.updateTabBarPreview(theme: theme, contentWidth: params.width)
    }

    private func updateTabBarPreview(theme: PresentationTheme, contentWidth: CGFloat) {
        guard let item = self.item else {
            return
        }

        var previewSettings = item.settings
        previewSettings.isBottomBarVisible = true

        self.componentIdsByItemId.removeAll()
        self.itemIdsByComponentId.removeAll()
        self.itemFrames.removeAll()

        let makeComponentItem: (RGBottomBarItemId) -> TabBarComponent.Item = { [weak self] id in
            let componentId = AnyHashable("rg.preview.\(id.rawValue)")
            self?.componentIdsByItemId[id] = componentId
            self?.itemIdsByComponentId[componentId] = id

            let icon: TabBarComponent.Item.Content.CustomItem.Icon
            switch id {
            case .contacts:
                icon = .animation(name: "TabContacts", offset: .zero)
            case .calls:
                icon = .animation(name: "TabCalls", offset: .zero)
            case .chats:
                icon = .animation(name: "TabChats", offset: .zero)
            case .settings:
                icon = .animation(name: "TabSettings", offset: .zero)
            case .search:
                icon = .bundleIcon(name: "Navigation/Search")
            }

            return TabBarComponent.Item(
                content: .customItem(TabBarComponent.Item.Content.CustomItem(id: componentId, title: item.itemTitles[id] ?? id.rawValue, icon: icon)),
                action: { _ in },
                doubleTapAction: nil,
                contextAction: nil
            )
        }

        let visibleBottomItems = previewSettings.visibleBottomItems
        let visibleComponentItems = visibleBottomItems.map(makeComponentItem)
        let externalComponentItem: TabBarComponent.Item?
        if let externalItem = previewSettings.externalItem, !previewSettings.hiddenItems.contains(externalItem) {
            externalComponentItem = makeComponentItem(externalItem)
        } else {
            externalComponentItem = nil
        }

        let selectedId = self.componentIdsByItemId[.chats] ?? visibleBottomItems.compactMap { self.componentIdsByItemId[$0] }.first ?? previewSettings.externalItem.flatMap { self.componentIdsByItemId[$0] }
        let previewSideInset: CGFloat = 12.0
        let availableWidth = max(120.0, contentWidth - previewSideInset * 2.0)
        let allButtonsHidden = visibleComponentItems.isEmpty && externalComponentItem == nil
        if allButtonsHidden {
            self.emptyBottomLabel.isHidden = false
            self.emptyBottomLabel.frame = CGRect(x: previewSideInset, y: 130.0, width: availableWidth, height: 64.0)
            self.tabBarComponentView.view?.isHidden = true
            self.bottomFrame = self.emptyBottomLabel.frame
            self.externalFrame = CGRect(x: previewSideInset + availableWidth - 64.0, y: 130.0, width: 64.0, height: 64.0)
            self.externalDropView.isHidden = true
            return
        } else {
            self.emptyBottomLabel.isHidden = true
        }
        let tabBarSize = self.tabBarComponentView.update(
            transition: .immediate,
            component: AnyComponent(RGConfigurableTabBarComponent(
                theme: theme,
                strings: item.strings,
                items: visibleComponentItems,
                externalItem: externalComponentItem,
                search: previewSettings.isVisible(.search) ? TabBarComponent.Search(isActive: false, activate: {}, deactivate: {}) : nil,
                selectedId: selectedId,
                outerInsets: .zero,
                showItemTitles: previewSettings.showLabels,
                rgWidthPercent: previewSettings.automaticWidth ? 0 : RGTabBarLayoutPolicy.normalizedPercent(previewSettings.buttonWidthFillRatio)
            )),
            environment: {},
            containerSize: CGSize(width: availableWidth, height: 80.0)
        )

        if let tabBarView = self.tabBarComponentView.view {
            if tabBarView.superview !== self.backgroundView {
                self.backgroundView.addSubview(tabBarView)
            }
            tabBarView.isHidden = false

            let tabBarX = previewSideInset + floor((availableWidth - tabBarSize.width) * 0.5)
            let tabBarFrame = CGRect(origin: CGPoint(x: tabBarX, y: 130.0), size: tabBarSize)
            tabBarView.frame = tabBarFrame
            tabBarView.isUserInteractionEnabled = false
            tabBarView.alpha = item.settings.isBottomBarVisible ? 1.0 : 0.45

            for (componentId, itemId) in self.itemIdsByComponentId {
                if let componentView = tabBarView as? RGConfigurableTabBarComponent.View, let frame = componentView.frameForItem(id: componentId) {
                    self.itemFrames[itemId] = self.backgroundView.convert(frame, from: componentView)
                }
            }

            let previewCapsuleItems = visibleBottomItems + (previewSettings.isVisible(.search) ? previewSettings.externalItem.map { [$0] } ?? [] : [])
            let bottomItemFrames = previewCapsuleItems.compactMap { self.itemFrames[$0] }
            self.bottomFrame = bottomItemFrames.reduce(CGRect.null) { partialResult, frame in
                return partialResult.isNull ? frame : partialResult.union(frame)
            }
            if self.bottomFrame.isNull {
                self.bottomFrame = CGRect(x: tabBarFrame.minX, y: tabBarFrame.minY, width: max(48.0, tabBarFrame.width - 72.0), height: 64.0)
            }

            let fixedExternalFrame = CGRect(x: previewSideInset + availableWidth - 64.0, y: tabBarFrame.minY, width: 64.0, height: 64.0)
            if let externalItem = previewSettings.externalItem, let frame = self.itemFrames[externalItem] {
                self.externalFrame = frame

            } else {
                self.externalFrame = fixedExternalFrame
            }

            let hasExternalSlotContent = externalComponentItem != nil
            self.externalDropView.isHidden = true
            self.externalDropView.frame = self.externalFrame
            self.externalDropView.layer.cornerRadius = 32.0
            self.externalDropView.layer.borderWidth = 1.0
            self.externalDropView.layer.borderColor = theme.list.itemBlocksSeparatorColor.cgColor
            self.externalDropView.backgroundColor = theme.list.itemInputField.backgroundColor.withAlphaComponent(0.55)
            if !hasExternalSlotContent {
                self.backgroundView.bringSubviewToFront(self.externalDropView)
            }
        }
    }

    @objc private func panGesture(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self.backgroundView)
        switch gesture.state {
        case .began:
            self.draggingItem = self.itemId(at: point)
        case .ended, .cancelled:
            guard let draggingItem = self.draggingItem else {
                return
            }
            self.draggingItem = nil
            if self.item?.settings.isVisible(.search) == false, !self.bottomFrame.contains(point), self.externalFrame.insetBy(dx: -16.0, dy: -16.0).contains(point) {
                self.item?.update { settings in
                    settings.moveToExternal(draggingItem)
                }
            } else if self.bottomFrame.insetBy(dx: -16.0, dy: -16.0).contains(point) {
                let visibleItems = self.previewVisibleBottomItems()
                var targetIndex = self.targetBottomIndex(at: point, visibleItems: visibleItems)
                if let sourceIndex = visibleItems.firstIndex(of: draggingItem), targetIndex > sourceIndex {
                    targetIndex -= 1
                }
                self.item?.update { settings in
                    settings.moveToBottom(draggingItem, at: targetIndex)
                }
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGestureRecognizer = self.panGestureRecognizer, gestureRecognizer === panGestureRecognizer {
            let point = gestureRecognizer.location(in: self.backgroundView)
            return self.itemId(at: point) != nil
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self.backgroundView)
        if self.topSearchView.frame.contains(point) || self.bottomBarTitleLabel.frame.contains(point) {
            return false
        }
        return true
    }

    private func itemId(at point: CGPoint) -> RGBottomBarItemId? {
        if let match = self.itemFrames.first(where: { $0.value.insetBy(dx: -8.0, dy: -8.0).contains(point) }) {
            return match.key
        }
        return nil
    }

    private func previewVisibleBottomItems() -> [RGBottomBarItemId] {
        guard let item = self.item else {
            return []
        }
        var settings = item.settings
        settings.isBottomBarVisible = true
        return settings.visibleBottomItems
    }

    private func targetBottomIndex(at point: CGPoint, visibleItems: [RGBottomBarItemId]) -> Int {
        guard !visibleItems.isEmpty else {
            return 0
        }
        for (index, id) in visibleItems.enumerated() {
            guard let frame = self.itemFrames[id] else {
                continue
            }
            if point.x < frame.midX {
                return index
            }
        }
        return visibleItems.count
    }
}

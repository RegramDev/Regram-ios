// MARK: Regram — attach long-press copying to native settings without changing their controls.
import AccountContext
import Display
import Foundation
import ItemListUI
import RGStrings
import SwiftSignalKit
import UIKit

public final class RGSettingsItemTag: ItemListItemTag {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    public func isEqual(to other: ItemListItemTag) -> Bool { (other as? RGSettingsItemTag)?.identifier == identifier }
}

private final class RGSettingsCopyGesture: UILongPressGestureRecognizer {
    var copyLink: (() -> Void)?
    init() { super.init(target: nil, action: nil); addTarget(self, action: #selector(copySetting)); minimumPressDuration = 0.6; cancelsTouchesInView = true }
    @objc private func copySetting() { if state == .began { copyLink?() } }
}

private final class RGSettingsLinkItem: ListViewItem, ItemListItem {
    let base: ListViewItem
    let destination: RGSettingsDestination
    init(base: ListViewItem, destination: RGSettingsDestination) { self.base = base; self.destination = destination }
    var sectionId: ItemListSectionId { (base as? ItemListItem)?.sectionId ?? 0 }
    var tag: ItemListItemTag? { (base as? ItemListItem)?.tag }
    var isAlwaysPlain: Bool { (base as? ItemListItem)?.isAlwaysPlain ?? false }
    var requestsNoInset: Bool { (base as? ItemListItem)?.requestsNoInset ?? false }
    var neighborDescriptor: AnyEquatable { base.neighborDescriptor }
    var selectable: Bool { base.selectable }
    var approximateHeight: CGFloat { base.approximateHeight }
    var accessoryItem: ListViewAccessoryItem? { base.accessoryItem }
    var headerAccessoryItem: ListViewAccessoryItem? { base.headerAccessoryItem }
    var pinToEdgeWithInset: Bool { base.pinToEdgeWithInset }
    func selected(listView: ListView) { base.selected(listView: listView) }
    private func configure(_ node: ListViewItemNode) {
        guard !node.isLayerBacked else { return }
        let gesture = node.view.gestureRecognizers?.compactMap { $0 as? RGSettingsCopyGesture }.first ?? RGSettingsCopyGesture()
        let url = destination.url
        gesture.copyLink = { UIPasteboard.general.string = url.absoluteString; UINotificationFeedbackGenerator().notificationOccurred(.success) }
        if gesture.view == nil { node.view.addGestureRecognizer(gesture) }
    }
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        base.nodeConfiguredForParams(async: async, params: params, synchronousLoads: synchronousLoads, neighbors: neighbors, completion: { node, apply in
            self.configure(node); completion(node, apply)
        })
    }
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        base.updateNode(async: async, node: node, params: params, neighbors: neighbors, animation: animation, completion: { layout, apply in
            completion(layout, { value in self.configure(node()); apply(value) })
        })
    }
}

public func rgSettingsLinkItem(_ item: ListViewItem, destination: RGSettingsDestination?) -> ListViewItem {
    guard let destination else { return item }
    return RGSettingsLinkItem(base: item, destination: destination)
}

public func rgSettingsScrollTarget<T: ItemListNodeEntry>(_ entries: [T], item: String?) -> ListViewScrollToItem? {
    guard let item, let index = entries.firstIndex(where: { ($0.tag as? RGSettingsItemTag)?.identifier == item }) else { return nil }
    return ListViewScrollToItem(index: index, position: .visible, animated: false, curve: .Default(duration: nil), directionHint: .Down)
}

// Short settings lists use the main queue so text-driven row updates cannot race touch timers.
public final class RGSettingsListController: ItemListController {
    override public func loadDisplayNode() {
        super.loadDisplayNode()
        (self.displayNode as? ItemListControllerNode)?.listNode.useMainQueueTransactions = true
    }
}

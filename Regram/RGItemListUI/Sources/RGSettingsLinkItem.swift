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
    public var focusSetting: String?
    public var focusColor: UIColor = .systemBlue
    private var focusGeneration = 0
    private var didHighlightFocus = false
    private weak var focusOverlay: UIView?

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let focusSetting, !self.didHighlightFocus else { return }
        self.focusGeneration += 1
        let generation = self.focusGeneration
        // Transactions and navigation can finish in either order; wait for the actual tagged node.
        for delay in [0.1, 0.4, 0.8, 1.4] {
            Queue.mainQueue().after(delay, { [weak self] in
                guard let self, self.focusGeneration == generation, !self.didHighlightFocus,
                      self.view.window != nil,
                      let node = self.itemNode(forTag: RGSettingsItemTag(focusSetting)), !node.isLayerBacked,
                      node.bounds.height > 0 else { return }
                self.didHighlightFocus = true
                let overlay = UIView(frame: node.bounds.insetBy(dx: 4, dy: 1))
                overlay.isUserInteractionEnabled = false
                overlay.isAccessibilityElement = false
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                overlay.backgroundColor = self.focusColor.withAlphaComponent(0.16)
                overlay.layer.borderColor = self.focusColor.withAlphaComponent(0.85).cgColor
                overlay.layer.borderWidth = 2
                overlay.layer.cornerRadius = 12
                node.view.addSubview(overlay)
                self.focusOverlay = overlay
                UIView.animate(withDuration: 0.4, delay: 2.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                    overlay.alpha = 0
                }, completion: { _ in overlay.removeFromSuperview() })
            })
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        self.focusGeneration += 1
        self.focusOverlay?.removeFromSuperview()
        super.viewWillDisappear(animated)
    }

    override public func loadDisplayNode() {
        super.loadDisplayNode()
        (self.displayNode as? ItemListControllerNode)?.listNode.useMainQueueTransactions = true
    }
}

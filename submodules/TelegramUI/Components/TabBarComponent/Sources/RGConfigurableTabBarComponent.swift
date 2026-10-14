// MARK: Regram — arrange the upstream bar; keep its glass, selection and gestures intact.
import RGSimpleSettings
import UIKit
import AsyncDisplayKit
import ComponentFlow
import Display
import TelegramPresentationData

public final class RGConfigurableTabBarComponent: Component {
    public let theme: PresentationTheme
    public let strings: PresentationStrings
    public let items: [TabBarComponent.Item]
    public let externalItem: TabBarComponent.Item?
    public let search: TabBarComponent.Search?
    public let selectedId: AnyHashable?
    public let outerInsets: UIEdgeInsets
    public let showItemTitles: Bool
    public let rgWidthPercent: Int32?
    public init(theme: PresentationTheme, strings: PresentationStrings, items: [TabBarComponent.Item], externalItem: TabBarComponent.Item?, search: TabBarComponent.Search?, selectedId: AnyHashable?, outerInsets: UIEdgeInsets, showItemTitles: Bool, rgWidthPercent: Int32?) {
        self.theme = theme; self.strings = strings; self.items = items; self.externalItem = externalItem; self.search = search; self.selectedId = selectedId; self.outerInsets = outerInsets; self.showItemTitles = showItemTitles; self.rgWidthPercent = rgWidthPercent
    }
    public static func ==(lhs: RGConfigurableTabBarComponent, rhs: RGConfigurableTabBarComponent) -> Bool {
        lhs.theme === rhs.theme && lhs.strings === rhs.strings && lhs.items == rhs.items && lhs.externalItem == rhs.externalItem && lhs.search == rhs.search && lhs.selectedId == rhs.selectedId && lhs.outerInsets == rhs.outerInsets && lhs.showItemTitles == rhs.showItemTitles && lhs.rgWidthPercent == rhs.rgWidthPercent
    }
    public final class View: UIView {
        private let bar = ComponentView<Empty>()
        private let standalone = ComponentView<Empty>()
        private var itemIds: [AnyHashable] = []
        private var standaloneId: AnyHashable?
        public var currentSearchNode: ASDisplayNode? { (bar.view as? TabBarComponent.View)?.currentSearchNode }
        public func frameForItem(id: AnyHashable) -> CGRect? {
            let component = id == standaloneId ? standalone : bar
            let index = id == standaloneId ? 0 : itemIds.firstIndex(of: id)
            guard let index, let view = component.view as? TabBarComponent.View, let frame = view.frameForItem(at: index) else { return nil }
            return convert(frame, from: view)
        }
        fileprivate func update(component: RGConfigurableTabBarComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            itemIds = component.items.map { item in
                switch item.content { case let .tabBarItem(value): return AnyHashable(ObjectIdentifier(value)); case let .customItem(value): return value.id }
            }
            if let item = component.externalItem {
                switch item.content { case let .tabBarItem(value): standaloneId = AnyHashable(ObjectIdentifier(value)); case let .customItem(value): standaloneId = value.id }
            } else { standaloneId = nil }
            let percent = component.rgWidthPercent ?? 0
            let width = CGFloat(RGTabBarLayoutPolicy.width(containerWidth: Double(availableSize.width), itemCount: component.items.count, percent: percent, searchButtonWidth: component.externalItem == nil ? 0 : 72))
            let externalWidth: CGFloat = component.externalItem == nil ? 0 : 72
            var height: CGFloat = 0
            for (target, items, x, containerWidth) in [(bar, component.items, CGFloat(0), max(0, width - externalWidth)), (standalone, component.externalItem.map { [$0] } ?? [], max(0, width - 64), CGFloat(64))] {
                guard !items.isEmpty else { target.view?.removeFromSuperview(); continue }
                let size = target.update(transition: transition, component: AnyComponent(TabBarComponent(theme: component.theme, strings: component.strings, items: items, search: nil, selectedId: component.selectedId, outerInsets: component.outerInsets, showItemTitles: component.showItemTitles)), environment: {}, containerSize: CGSize(width: containerWidth, height: availableSize.height))
                if let view = target.view { if view.superview == nil { addSubview(view) }; transition.setFrame(view: view, frame: CGRect(origin: CGPoint(x: x, y: 0), size: size)) }
                height = max(height, size.height)
            }
            return CGSize(width: height == 0 ? 0 : width, height: height)
        }
    }
    public func makeView() -> View { View(frame: .zero) }
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize { view.update(component: self, availableSize: availableSize, transition: transition) }
}

import ComponentFlow
import Display
import Foundation
import HorizontalTabsComponent
import TelegramPresentationData
import UIKit

/// The same native horizontal bar used by chat folders, with stable navigation geometry.
final class RGSettingsCategoryTabsNode: NavigationBarContentNode {
    private let component = ComponentView<Empty>()
    private var theme: PresentationTheme
    private var titles: [String]
    private var selectedIndex: Int
    private var selected: (Int) -> Void
    private var validLayout: (CGSize, CGFloat, CGFloat)?

    init(theme: PresentationTheme, titles: [String], selectedIndex: Int, selected: @escaping (Int) -> Void) {
        self.theme = theme
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.selected = selected
        super.init()
    }

    func update(theme: PresentationTheme, titles: [String], selectedIndex: Int, selected: @escaping (Int) -> Void) {
        let changedSelection = self.selectedIndex != selectedIndex
        self.theme = theme
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.selected = selected
        if let (size, leftInset, rightInset) = self.validLayout {
            let _ = self.updateLayout(size: size, leftInset: leftInset, rightInset: rightInset, transition: changedSelection ? .animated(duration: 0.2, curve: .easeInOut) : .immediate)
        }
    }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        self.validLayout = (size, leftInset, rightInset)
        let inset: CGFloat = 16.0
        let width = max(0.0, size.width - leftInset - rightInset - inset * 2.0)
        let barSize = self.component.update(
            transition: ComponentTransition(transition),
            component: AnyComponent(HorizontalTabsComponent(
                context: nil,
                theme: self.theme,
                tabs: self.titles.enumerated().map { index, title in
                    HorizontalTabsComponent.Tab(id: AnyHashable(index), content: .title(.init(text: title, entities: [], enableAnimations: false)), badge: nil, action: { [weak self] in
                        // Let the state source deduplicate. A rendered selection may lag a rapid tap.
                        guard let self, self.titles.indices.contains(index) else { return }
                        self.selected(index)
                    })
                },
                selectedTab: AnyHashable(self.selectedIndex),
                isEditing: false,
                layout: .fill,
                liftWhileSwitching: false
            )),
            environment: {},
            containerSize: CGSize(width: width, height: 44.0)
        )
        if let view = self.component.view {
            if view.superview == nil { self.view.addSubview(view) }
            // Every visible part of the bar stays inside its parent's hit-test bounds.
            transition.updateFrame(view: view, frame: CGRect(origin: CGPoint(x: leftInset + inset, y: 4.0), size: barSize))
        }
        return CGSize(width: size.width, height: self.nominalHeight)
    }

    override var nominalHeight: CGFloat { 56.0 }
    override var mode: NavigationBarContentMode { .expansion }
}

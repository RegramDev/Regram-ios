#!/usr/bin/env python3
"""Exercise production tab callbacks with retained gestures, tab rebuilds and delayed readiness."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', help='Prove the reported stale-index crash against this revision')
args = parser.parse_args()


def source(path):
    if args.baseline:
        return subprocess.check_output(['git', 'show', args.baseline + ':' + path], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


node = source('submodules/TabBarUI/Sources/TabBarContollerNode.swift')
start = node.index('        let makeNativeComponentItem:')
factory = node[start:node.index('\n        let makeComponentItem:', start)]
controller = source('submodules/TabBarUI/Sources/TabBarController.swift')
start = controller.index('        self.displayNode = TabBarControllerNode(')
callbacks = controller[start:controller.index('\n        // MARK: Regram — end external search', start)]
start = controller.index('    public func setControllers(')
start = controller.index('\n', start) + 1
rebuild_prelude = controller[start:controller.index('        var updatedSelectedIndex:', start)]

fixture = r'''
import Foundation
import CoreFoundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { print("FAIL: " + message); exit(1) }
}
func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
func CACurrentMediaTime() -> Double { CFAbsoluteTimeGetCurrent() }
class ASDisplayNode {}
final class ContextGesture {}
final class ContextExtractedContentContainingView {}
enum TabBarItemSwipeDirection { case left }
enum ToolbarActionOption { case action }
struct ContainerViewLayout { struct Insets { var bottom: CGFloat = 0 }; var intrinsicInsets = Insets() }
enum ContainedViewLayoutTransition { case immediate }
final class UITabBarItem {}
struct TabBarNodeItem { let item: UITabBarItem }
protocol TabBarContainedController { func presentTabBarPreviewingController(sourceNodes: [ASDisplayNode]) }
class ViewController {
    let tabBarItem = UITabBarItem()
    let ready = Promise<Bool>(true)
    let name: String
    var toolbar: Int? { nil }
    var layouts = 0, doubleTaps = 0, contexts = 0, swipes = 0, scrolls = 0, previews = 0
    var tabBarItemDebugTapAction: (() -> Void)?
    var scrollToTopWithTabBar: (() -> Void)?
    var longTapWithTabBar: (() -> Void)?
    init(_ name: String) {
        self.name = name
        self.scrollToTopWithTabBar = { [weak self] in self?.scrolls += 1 }
    }
    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) { layouts += 1 }
    func tabBarItemHasDoubleTapAction() -> Bool { true }
    func tabBarItemPerformDoubleTapAction() { doubleTaps += 1 }
    func tabBarItemContextAction(sourceView: ContextExtractedContentContainingView, gesture: ContextGesture) { contexts += 1 }
    func tabBarItemSwipeAction(direction: TabBarItemSwipeDirection) { swipes += 1 }
    func toolbarActionSelected(action: ToolbarActionOption) {}
    func tabBarDisabledAction() {}
    func tabBarActivateSearch() {}
    func tabBarDeactivateSearch() {}
}
final class Screen: ViewController, TabBarContainedController {
    func presentTabBarPreviewingController(sourceNodes: [ASDisplayNode]) { previews += 1 }
}
enum TabBarComponent {
    struct Item {
        enum Content { case tabBarItem(UITabBarItem) }
        let content: Content
        let action: (Bool) -> Void
        let doubleTapAction: (() -> Void)?
        let contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
    }
}
final class TabBarControllerNode {
    var tabBarItems: [TabBarNodeItem] = []
    var tabBarHidden = false
    var onLayout: (() -> Void)?
    let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    let itemHasDoubleTapAction: (Int) -> Bool
    let itemDoubleTapped: (Int) -> Void
    let contextAction: (Int, ContextExtractedContentContainingView, ContextGesture) -> Void
    let swipeAction: (Int, TabBarItemSwipeDirection) -> Void
    init(theme: Int, strings: Int,
         itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void,
         itemHasDoubleTapAction: @escaping (Int) -> Bool,
         itemDoubleTapped: @escaping (Int) -> Void,
         contextAction: @escaping (Int, ContextExtractedContentContainingView, ContextGesture) -> Void,
         swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void,
         toolbarActionSelected: @escaping (ToolbarActionOption) -> Void,
         disabledPressed: @escaping () -> Void, activateSearch: @escaping () -> Void, deactivateSearch: @escaping () -> Void) {
        self.itemSelected = itemSelected; self.itemHasDoubleTapAction = itemHasDoubleTapAction
        self.itemDoubleTapped = itemDoubleTapped; self.contextAction = contextAction; self.swipeAction = swipeAction
    }
    func containerLayoutUpdated(_ layout: ContainerViewLayout, toolbar: Int?, transition: ContainedViewLayoutTransition) -> CGFloat? {
        let callback = onLayout; onLayout = nil; callback?(); return 72
    }
    func makeItem(_ index: Int) -> TabBarComponent.Item {
        FACTORY
        return makeNativeComponentItem(index, tabBarItems[index])!
    }
}
final class Host {
    var controllers: [ViewController] = []
    var currentController: ViewController?
    var selectedIndex = 0 { didSet { currentController = controllers.indices.contains(selectedIndex) ? controllers[selectedIndex] : nil } }
    var debugTapCounter: (Double, Int) = (0, 0)
    var validLayout: ContainerViewLayout? = ContainerViewLayout()
    let pendingControllerDisposable = MetaDisposable()
    let theme = 0, strings = 0
    var displayNode: TabBarControllerNode!
    var tabBarControllerNode: TabBarControllerNode { displayNode }
    init(_ controllers: [ViewController]) { install(); replace(controllers) }
    func install() { CALLBACKS }
    func rgCancelInteractiveReturnToChats() {}
    func replace(_ controllers: [ViewController]) {
        REBUILD_PRELUDE
        self.controllers = controllers
        self.displayNode.tabBarItems = controllers.map { TabBarNodeItem(item: $0.tabBarItem) }
        selectedIndex = 0
    }
    deinit { pendingControllerDisposable.dispose() }
}
@main enum Tests { static func main() {
    let contacts = Screen("contacts"), calls = Screen("calls"), chats = Screen("chats"), settings = Screen("settings")
    let all: [ViewController] = [contacts, calls, chats, settings]
    let host = Host(all), node = host.displayNode!
    let oldSettings = node.makeItem(3), oldContacts = node.makeItem(0), oldChats = node.makeItem(2)
    host.replace([chats, settings])
    // This is the reported stack: a retained Settings action still carried index 3 after four tabs became two.
    oldSettings.action(false); pump()
    check(host.currentController === settings, "Retained Settings action survives four-to-two tabs")
    oldSettings.doubleTapAction?()
    oldSettings.contextAction?(ContextGesture(), ContextExtractedContentContainingView())
    oldSettings.action(true)
    check(settings.doubleTaps == 1 && settings.contexts == 1 && settings.previews == 1, "Retained auxiliary actions resolve the same live item")
    let previousLayouts = contacts.layouts
    oldContacts.action(false); oldContacts.action(true); oldContacts.doubleTapAction?()
    oldContacts.contextAction?(ContextGesture(), ContextExtractedContentContainingView())
    check(contacts.layouts == previousLayouts && contacts.doubleTaps == 0 && contacts.contexts == 0 && contacts.previews == 0, "Removed item actions are ignored")
    host.replace([settings, calls, contacts, chats])
    oldSettings.action(false); pump()
    check(host.currentController === settings, "Retained item follows reorder without changing tab count")
    oldChats.action(false); pump()
    check(host.currentController === chats && host.selectedIndex == 3, "Retained Chats action follows reorder")
    host.replace([chats, settings])
    // Deliberately leave a stale node list to exercise the controller boundary, not only the component adapter.
    node.tabBarItems = all.map { TabBarNodeItem(item: $0.tabBarItem) }
    for index in [-1, 2, 3, Int.max] {
        node.itemSelected(index, false, []); node.itemSelected(index, true, [])
        check(!node.itemHasDoubleTapAction(index), "Invalid double-tap query is ignored")
        node.itemDoubleTapped(index)
        node.contextAction(index, ContextExtractedContentContainingView(), ContextGesture())
        node.swipeAction(index, .left)
    }
    check(host.currentController === chats && settings.doubleTaps == 1 && settings.contexts == 1, "Stale node bounds cannot expose a missing controller")
    host.replace([chats, settings])
    node.onLayout = { host.replace([settings, chats]) }
    node.itemSelected(1, false, []); pump()
    check(host.currentController === settings && host.selectedIndex == 0, "Reentrant layout reorder keeps the selected controller identity")
    host.replace([chats, settings])
    node.onLayout = { host.replace([chats]) }
    node.itemSelected(1, false, []); pump()
    check(host.currentController === chats, "Reentrant removal cannot subscribe or select the removed controller")

    let pending = Screen("pending"), values = ValuePipe<Bool>()
    pending.ready.set(values.signal())
    host.replace([chats, pending])
    node.itemSelected(1, false, [])
    // An in-flight callback may observe a reordered list before a root rebuild cancels it.
    host.controllers = [pending, chats]; node.tabBarItems = host.controllers.map { TabBarNodeItem(item: $0.tabBarItem) }
    host.selectedIndex = 1
    values.putNext(true); pump()
    check(host.currentController === pending && host.selectedIndex == 0, "Readiness resolves the controller's current index")
    let removed = Screen("removed"), later = ValuePipe<Bool>()
    removed.ready.set(later.signal())
    host.replace([chats, removed]); node.itemSelected(1, false, [])
    host.controllers = [chats]; node.tabBarItems = [TabBarNodeItem(item: chats.tabBarItem)]; host.selectedIndex = 0
    later.putNext(true); pump()
    check(host.currentController === chats, "Late readiness for a removed controller is ignored")
    let cancelled = Screen("cancelled"), afterRebuild = ValuePipe<Bool>()
    cancelled.ready.set(afterRebuild.signal())
    host.replace([chats, cancelled]); node.itemSelected(1, false, [])
    host.replace([chats]); host.replace([chats, cancelled])
    afterRebuild.putNext(true); pump()
    check(host.currentController === chats, "A root rebuild cancels readiness even when the same tab returns")
    let unchanged = Screen("unchanged"), afterSameList = ValuePipe<Bool>()
    unchanged.ready.set(afterSameList.signal())
    host.replace([chats, unchanged]); node.itemSelected(1, false, [])
    host.replace([chats, unchanged]); afterSameList.putNext(true); pump()
    check(host.currentController === unchanged, "An unchanged root list preserves the pending selection")
    host.replace([chats, settings]); host.selectedIndex = 1
    let beforeScroll = settings.scrolls
    node.itemSelected(1, false, []); pump()
    check(settings.scrolls == beforeScroll + 1, "Selecting the current tab still scrolls to top")
    for _ in 0..<30 {
        host.replace(all); oldSettings.action(false); pump()
        check(host.currentController === settings, "Repeated enable keeps Settings identity")
        host.replace([chats, settings]); oldChats.action(false); pump()
        check(host.currentController === chats, "Repeated disable keeps Chats identity")
    }
    print("Tab selection regressions:", checks, "checks passed")
}}
'''.replace('FACTORY', factory).replace('CALLBACKS', callbacks).replace('REBUILD_PRELUDE', rebuild_prelude)

with tempfile.TemporaryDirectory(prefix='regram-tab-selection-') as temporary:
    folder = Path(temporary)
    harness = folder / 'Tests.swift'
    harness.write_text(fixture)
    signals = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    binary = folder / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-g',
                    *map(str, signals), str(harness), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    print(result.stdout, end='')
    if args.baseline:
        if result.returncode == 0 or 'Index out of range' not in result.stderr:
            raise SystemExit('Baseline did not reproduce the stale-index crash: ' + result.stderr)
        print('Baseline reproduced the reported out-of-range trap in the production tab selection callback.')
    elif result.returncode:
        raise SystemExit(result.stderr or result.returncode)

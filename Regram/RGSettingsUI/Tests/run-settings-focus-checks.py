#!/usr/bin/env python3
"""Run native focus lifecycle with real item insets, delayed rows and interrupted callbacks."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
source = (root / 'Regram/RGItemListUI/Sources/RGSettingsLinkItem.swift').read_text()
start = source.index('public final class RGSettingsListController:')
fields_end = source.index('    private let categoryTabsDisposable', start)
methods_start = source.index('    override public func viewDidAppear', fields_end)
end = source.index('    override public func loadDisplayNode()', methods_start)
# Exercise the actual focus fields and lifecycle, without pulling unrelated category-tab binding
# and its UI/signal dependencies into this Foundation boundary fixture.
focus = source[start:fields_end] + source[methods_start:end] + '}\n'
fixture = r'''
import Foundation
import CoreGraphics
public class UIView { var window: Int? = 1 }
final class Queue {
    static let main = Queue()
    static func mainQueue() -> Queue { main }
    var now: Double = 0
    var pending: [(Double, () -> Void)] = []
    func after(_ delay: Double, _ action: @escaping () -> Void) { pending.append((now + delay, action)) }
    func advance(to time: Double) {
        while let index = pending.indices.filter({ pending[$0].0 <= time }).min(by: { pending[$0].0 < pending[$1].0 }) {
            let (deadline, action) = pending.remove(at: index); now = deadline; action()
        }
        now = time
    }
}
final class RGSettingsItemTag { let key: String; init(_ value: String) { key = value } }
protocol ItemListItemNode { func displayHighlight() }
class ListViewItemNode {
    let view = UIView()
    // Grouped rows include spacing in their bounds; native drawing owns their content and masks.
    var bounds = CGRect(x: 0, y: -36, width: 390, height: 88)
    var isLayerBacked = false
    var highlightCount = 0
}
final class NativeItemNode: ListViewItemNode, ItemListItemNode {
    func displayHighlight() { highlightCount += 1 }
}
public class ItemListController {
    let view = UIView()
    var nodes: [String: ListViewItemNode] = [:]
    public func viewDidAppear(_ animated: Bool) {}
    public func viewWillDisappear(_ animated: Bool) {}
    func itemNode(forTag tag: RGSettingsItemTag) -> ListViewItemNode? { nodes[tag.key] }
}
FOCUS
@main enum Checks {
    static func main() {
        let queue = Queue.main
        let controller = RGSettingsListController()
        controller.focusSetting = "hidePrivateChatActivities"
        controller.viewDidAppear(true)
        queue.advance(to: 0.5)
        let other = NativeItemNode(), target = NativeItemNode()
        controller.nodes["other"] = other
        controller.nodes["hidePrivateChatActivities"] = target
        queue.advance(to: 1.5)
        precondition(target.highlightCount == 1 && other.highlightCount == 0, "Use only the target row's native highlight, independent of grouped insets")
        queue.advance(to: 2.5)
        precondition(target.highlightCount == 1, "Use the native focus animation once; do not simulate pressed state")
        let interrupted = RGSettingsListController()
        interrupted.focusSetting = "late"
        interrupted.viewDidAppear(true); interrupted.viewWillDisappear(true)
        let late = NativeItemNode(); interrupted.nodes["late"] = late
        queue.advance(to: 4.0)
        precondition(late.highlightCount == 0, "Stale callbacks after navigation must not highlight")
        interrupted.viewDidAppear(true); queue.advance(to: 4.2)
        precondition(late.highlightCount == 1)
        interrupted.viewWillDisappear(true)
        let count = late.highlightCount
        queue.advance(to: 8.0)
        precondition(late.highlightCount == count, "An obsolete fade must not affect a later screen")
        let zero = RGSettingsListController(); zero.focusSetting = "zero"
        let zeroNode = NativeItemNode(); zeroNode.bounds.size.height = 0
        zero.nodes["zero"] = zeroNode; zero.viewDidAppear(false); queue.advance(to: 10)
        precondition(zeroNode.highlightCount == 0, "Wait for actual layout before highlighting")
        print("Settings focus passed: native row drawing with grouped insets, exact target, delayed layout, native animation ownership, navigation cancellation and stale callbacks.")
    }
}
'''.replace('FOCUS', focus)
with tempfile.TemporaryDirectory(prefix='regram-settings-focus-') as directory:
    work = Path(directory); swift = work / 'Checks.swift'; swift.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work/'checks')], check=True)
    subprocess.run([str(work/'checks')], check=True)

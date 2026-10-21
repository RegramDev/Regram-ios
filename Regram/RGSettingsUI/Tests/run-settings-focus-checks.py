#!/usr/bin/env python3
"""Run the production native settings focus lifecycle with delayed row availability."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
source = (root / 'Regram/RGItemListUI/Sources/RGSettingsLinkItem.swift').read_text()
start = source.index('public final class RGSettingsListController:')
end = source.index('    override public func loadDisplayNode()', start)
focus = source[start:end] + '}\n'
fixture = r'''
import Foundation
import CoreGraphics
public struct UIColor {
    public static let systemBlue = Self()
    func withAlphaComponent(_ value: CGFloat) -> Self { self }
    var cgColor: Int { 1 }
}
final class Layer { var borderColor: Int?; var borderWidth: CGFloat = 0; var cornerRadius: CGFloat = 0 }
public class UIView {
    struct Options: OptionSet { let rawValue: Int; static let beginFromCurrentState = Self(rawValue: 1), allowUserInteraction = Self(rawValue: 2) }
    struct Mask: OptionSet { let rawValue: Int; static let flexibleWidth = Self(rawValue: 1), flexibleHeight = Self(rawValue: 2) }
    static var completions: [() -> Void] = []
    static func animate(withDuration: Double, delay: Double, options: Options, animations: () -> Void, completion: @escaping (Bool) -> Void) { animations(); completions.append { completion(true) } }
    var window: Int? = 1
    var bounds: CGRect
    var isUserInteractionEnabled = true, isAccessibilityElement = true
    var autoresizingMask: Mask = [], backgroundColor: UIColor?, alpha: CGFloat = 1
    let layer = Layer()
    var children: [UIView] = []
    weak var parent: UIView?
    init(frame: CGRect = CGRect(x: 0, y: 0, width: 390, height: 50)) { bounds = frame }
    func addSubview(_ value: UIView) { children.append(value); value.parent = self }
    func removeFromSuperview() { parent?.children.removeAll { $0 === self }; parent = nil }
}
final class Queue {
    static let main = Queue()
    static func mainQueue() -> Queue { main }
    var pending: [() -> Void] = []
    func after(_ delay: Double, _ action: @escaping () -> Void) { pending.append(action) }
    func drain() { while !pending.isEmpty { pending.removeFirst()() } }
}
final class RGSettingsItemTag { let key: String; init(_ value: String) { key = value } }
final class ListViewItemNode { let view = UIView(); var bounds: CGRect { view.bounds }; var isLayerBacked = false }
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
        let controller = RGSettingsListController()
        controller.focusSetting = "hidePrivateChatActivities"
        controller.viewDidAppear(true)
        Queue.main.pending.removeFirst()()
        let other = ListViewItemNode(), target = ListViewItemNode()
        controller.nodes["other"] = other
        Queue.main.pending.removeFirst()()
        precondition(other.view.children.isEmpty)
        controller.nodes["hidePrivateChatActivities"] = target
        Queue.main.drain()
        precondition(target.view.children.count == 1 && other.view.children.isEmpty, "Wait for and highlight only the requested row")
        let overlay = target.view.children[0]
        precondition(!overlay.isUserInteractionEnabled && !overlay.isAccessibilityElement && overlay.layer.borderWidth == 2, "The visible focus marker must not block the switch")
        controller.viewWillDisappear(true)
        precondition(target.view.children.isEmpty, "Navigation cleans the marker")
        UIView.completions.removeFirst()()
        let interrupted = RGSettingsListController()
        interrupted.focusSetting = "late"
        interrupted.viewDidAppear(true); interrupted.viewWillDisappear(true)
        interrupted.nodes["late"] = target
        Queue.main.drain()
        precondition(target.view.children.isEmpty, "Stale callbacks after navigation must not mark a row")
        interrupted.viewDidAppear(true); Queue.main.drain()
        precondition(target.view.children.count == 1, "A later appearance can retry an unfinished focus")
        UIView.completions.removeFirst()()
        precondition(target.view.children.isEmpty, "The marker fades out after locating the setting")
        print("Settings focus passed: delayed rows, exact target, non-blocking marker, bounded retries, navigation cancellation and cleanup.")
    }
}
'''.replace('FOCUS', focus)
with tempfile.TemporaryDirectory(prefix='regram-settings-focus-') as directory:
    work = Path(directory); swift = work / 'Checks.swift'; swift.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work/'checks')], check=True)
    subprocess.run([str(work/'checks')], check=True)

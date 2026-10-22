"""Run production interactive-tab methods with a controllable UIKit lifecycle boundary.

Rendering is not simulated: the real UIKit helper is separately SDK-typechecked.
The boundary lets tests interrupt animation completions deterministically.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
controller = (root / 'submodules/TabBarUI/Sources/TabBarController.swift').read_text()
transition_source = (root / 'submodules/TabBarUI/Sources/RGRootTabBackTransition.swift').read_text().replace('import Display\n', '')
transition = transition_source.replace('import UIKit', 'import Foundation\nimport CoreGraphics')

def block(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

state = block(controller, '    private final class RGBackState')
methods = '\n'.join(block(controller, '    ' + signature) for signature in [
    'public func rgBeginInteractiveReturnToChats()',
    'public func rgUpdateInteractiveReturnToChats(progress:',
    'public func rgEndInteractiveReturnToChats(completed:',
    'private func rgCancelInteractiveReturnToChats()',
])
external_cleanup = block(controller, '        if !self.rgSwitchingInteractively, let state = self.rgBackState')
selection = block(controller, '    public var selectedIndex: Int')
fixture = r'''
import Foundation
import CoreGraphics
final class SharedDisplayLinkDriver {
    enum FramesPerSecond { case max }
    final class Link { func invalidate() {} }
    static let shared = SharedDisplayLinkDriver()
    func add(framesPerSecond: FramesPerSecond, _ update: @escaping (CGFloat) -> Void) -> Link { Link() }
}
final class Layer {
    var shadowColor: Int?; var shadowOpacity: Float = 0; var shadowRadius: CGFloat = 0; var shadowOffset = CGSize.zero
    var shadowPathWrites = 0
    var shadowPath: CGPath? { didSet { shadowPathWrites += 1 } }
    func removeAllAnimations() {}
}
struct UIColor { static let black = UIColor(); var cgColor: Int { 0 } }
struct UIBezierPath { let cgPath: CGPath; init(rect: CGRect) { cgPath = CGPath(rect: rect, transform: nil) } }
class UIView {
    struct AnimationOptions: OptionSet {
        let rawValue: Int
        static let curveEaseOut = Self(rawValue: 1), beginFromCurrentState = Self(rawValue: 2), allowUserInteraction = Self(rawValue: 4)
    }
    static var completions: [() -> Void] = []
    static func animate(withDuration: Double, delay: Double, options: AnimationOptions, animations: () -> Void, completion: @escaping (Bool) -> Void) {
        animations(); completions.append { completion(true) }
    }
    var window: Int? = 1
    var bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    var frame = CGRect.zero
    var transform = CGAffineTransform.identity
    var isUserInteractionEnabled = true
    var backgroundColor: UIColor?
    var alpha: CGFloat = 1
    let layer = Layer()
    var children: [UIView] = []
    weak var parent: UIView?
    var lastSnapshot: UIView?
    var canSnapshot = true
    func addSubview(_ view: UIView) { children.append(view); view.parent = self }
    func removeFromSuperview() { parent?.children.removeAll { $0 === self }; parent = nil }
    func convert(_ rect: CGRect, from: UIView) -> CGRect { rect }
    func snapshotView(afterScreenUpdates: Bool) -> UIView? {
        guard canSnapshot else { return nil }; let value = UIView(); lastSnapshot = value; return value
    }
}
final class TabItem { var animationName: String; init(_ name: String) { animationName = name } }
final class Child {
    let view = UIView(); let tabBarItem: TabItem
    init(_ name: String) { tabBarItem = TabItem(name) }
}
TRANSITION
final class Controller {
    STATE
    private var rgBackState: RGBackState?
    private var rgSwitchingInteractively = false
    var controllers = [Child("TabChats"), Child("Settings")]
    var currentController: Child?
    let view = UIView()
    var isNodeLoaded = true
    var _selectedIndex: Int? = 1
    SELECTION
    var animationRequests = 0
    var loseDestination = false
    var interactive: Bool { rgBackState != nil }
    init() { currentController = controllers[1] }
    func updateSelectedIndex(animated: Bool = false) {
        CLEANUP
        if animated { animationRequests += 1 }
        currentController = loseDestination && _selectedIndex == 0 ? nil : controllers[_selectedIndex!]
    }
    func externalSelection(_ index: Int) { selectedIndex = index }
    func interrupt() { rgCancelInteractiveReturnToChats() }
    METHODS
}
func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
@main enum Tests { static func main() {
    let controller = Controller()
    let chats = controller.controllers[0].view, settings = controller.controllers[1].view
    expect(controller.rgBeginInteractiveReturnToChats(), "Begin from Settings")
    expect(controller.selectedIndex == 0 && controller.view.children.count == 2, "Reveal real Chats under Settings snapshot")
    expect(!controller.rgBeginInteractiveReturnToChats(), "No overlapping transitions")
    let snapshot = settings.lastSnapshot!
    expect(snapshot.layer.shadowPath?.boundingBoxOfPath == snapshot.bounds, "Use the fixed snapshot bounds as the shadow outline")
    controller.rgUpdateInteractiveReturnToChats(progress: 0.4)
    expect(close(settings.lastSnapshot!.transform.tx, 156) && close(chats.transform.tx, -65.52), "Track finger and parallax")
    expect(snapshot.layer.shadowPathWrites == 1, "Interactive updates must reuse the outline instead of recalculating it")
    controller.rgEndInteractiveReturnToChats(completed: false, velocity: 0)
    controller.rgUpdateInteractiveReturnToChats(progress: 1)
    expect(close(settings.lastSnapshot!.transform.tx, 0), "No update after ending")
    UIView.completions.removeFirst()()
    expect(controller.selectedIndex == 1 && !controller.interactive && controller.view.children.isEmpty && chats.transform == .identity, "Cancellation restores Settings and clears transforms")
    expect(controller.rgBeginInteractiveReturnToChats(), "Begin again")
    controller.rgUpdateInteractiveReturnToChats(progress: 2)
    expect(close(settings.lastSnapshot!.transform.tx, 390), "Clamp progress")
    controller.rgEndInteractiveReturnToChats(completed: true, velocity: 900)
    UIView.completions.removeFirst()()
    expect(controller.selectedIndex == 0 && chats.transform == .identity && controller.view.children.isEmpty, "Completed pan keeps Chats")
    controller.externalSelection(1)
    expect(controller.rgBeginInteractiveReturnToChats(), "Begin before interruption")
    controller.rgEndInteractiveReturnToChats(completed: false, velocity: 0)
    let stale = UIView.completions.removeFirst()
    controller.interrupt()
    expect(controller.selectedIndex == 1 && controller.view.children.isEmpty, "Navigation or layout interruption restores source")
    expect(controller.rgBeginInteractiveReturnToChats(), "New gesture after interruption")
    stale()
    expect(controller.interactive && controller.selectedIndex == 0, "A stale completion cannot cancel a newer gesture")
    controller.externalSelection(1)
    expect(!controller.interactive && controller.view.children.isEmpty && chats.transform == .identity, "External navigation cleans overlay")
    expect(controller.rgBeginInteractiveReturnToChats(), "Begin before selecting the preview destination")
    controller.rgEndInteractiveReturnToChats(completed: false, velocity: 0)
    controller.externalSelection(0)
    UIView.completions.removeFirst()()
    expect(!controller.interactive && controller.selectedIndex == 0 && controller.view.children.isEmpty, "Explicitly selecting Chats commits even when the preview already selected it")
    controller.externalSelection(1)
    settings.canSnapshot = false
    expect(!controller.rgBeginInteractiveReturnToChats() && controller.selectedIndex == 1, "Snapshot failure leaves selection alone")
    settings.canSnapshot = true; controller.loseDestination = true
    expect(!controller.rgBeginInteractiveReturnToChats() && controller.selectedIndex == 1, "Missing destination rolls back")
    expect(controller.animationRequests == 4, "Only the four external selections may run the normal tab scale animation")
    print("Production root-tab transition passed: fixed shadow outline, finger tracking, cancellation, completion, interruption, stale callbacks and failed setup rollback.")
} }
'''.replace('TRANSITION', transition).replace('STATE', state).replace('METHODS', methods).replace('CLEANUP', external_cleanup).replace('SELECTION', selection)
with tempfile.TemporaryDirectory(prefix='regram-root-tab-transition-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], check=True)
    subprocess.run([str(folder / 'tests')], check=True)

    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    (folder / 'Transition.swift').write_text(transition_source)
    subprocess.run(['xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '5',
                    '-warnings-as-errors', '-target', 'arm64-apple-ios15.0-simulator', '-sdk', sdk,
                    str(root / 'submodules/Display/Source/DisplayLinkAnimator.swift'),
                    str(folder / 'Transition.swift')], check=True)
    print('Production root-tab transition passed real UIKit SDK typechecking (iOS 15 target).')

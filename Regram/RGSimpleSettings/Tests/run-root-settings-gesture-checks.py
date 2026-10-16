"""Exercise the production root-settings gesture delegate and typecheck UIKit wiring."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift').read_text()
a = source.index('private final class RGRootSettingsBackGestureDelegate:')
b = source.index('\npublic final class PeerInfoScreenImpl:', a)
delegate = source[a:b]
a = source.index('    @objc private func rgRootBackSwiped(')
b = source.index('\n\n    let context:', a)
handler = source[a:b]
a = source.index('    private func rgAttachRootBackGesture()')
b = source.index('    private var rgCanReturnToChats:', a)
attach = source[a:b]
a = source.index('        // MARK: Regram — root settings accepts rightward content pans;')
b = source.index('\n\n    }', a)
registration = source[a:b]
fixture = '''
import Foundation
import CoreGraphics
protocol UIGestureRecognizerDelegate {}
class UIView: NSObject {
    var bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    weak var superview: UIView?
}
class UIControl: UIView {}
class UITextField: UIControl {}
class UIScrollView: UIView {
    var alwaysBounceHorizontal = false
    var contentSize = CGSize(width: 390, height: 1600)
}
class UITextView: UIScrollView {}
class UIGestureRecognizer: NSObject { var view: UIView? }
class UIPanGestureRecognizer: UIGestureRecognizer {
    var movement = CGPoint.zero
    var speed = CGPoint.zero
    func translation(in view: UIView?) -> CGPoint { movement }
    func velocity(in view: UIView?) -> CGPoint { speed }
}
class UITouch: NSObject { var view: UIView?; init(_ view: UIView?) { self.view = view } }
DELEGATE
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print(message); exit(1) }
}
@main enum Tests { static func main() {
    let root = UIView(), content = UIView(), list = UIScrollView()
    list.superview = root; content.superview = list
    var allowed = true
    let delegate = RGRootSettingsBackGestureDelegate(canBegin: { allowed })
    let pan = UIPanGestureRecognizer(); pan.view = root
    pan.movement = CGPoint(x: 16, y: 2); pan.speed = CGPoint(x: 220, y: 20)
    expect(delegate.gestureRecognizerShouldBegin(pan), "A rightward pan in the content area should begin")
    expect(delegate.gestureRecognizer(pan, shouldReceive: UITouch(content)), "Ordinary content should permit a full-width pan")
    for point in [CGPoint(x: 10, y: 40), CGPoint(x: -20, y: 0), CGPoint(x: 10, y: 10)] {
        pan.movement = point; pan.speed = CGPoint(x: 800, y: 0)
        expect(!delegate.gestureRecognizerShouldBegin(pan), "Vertical, leftward and diagonal movement must not navigate")
    }
    pan.movement = .zero; pan.speed = CGPoint(x: 400, y: 30)
    expect(delegate.gestureRecognizerShouldBegin(pan), "A clear rightward velocity can start the pan")
    allowed = false
    expect(!delegate.gestureRecognizerShouldBegin(pan) && !delegate.gestureRecognizer(pan, shouldReceive: UITouch(content)), "The root/top/editing/visibility guard must gate touch and recognition")
    allowed = true
    for control in [UIControl(), UITextField(), UITextView()] as [UIView] {
        let nested = UIView(); nested.superview = control; control.superview = list
        expect(!delegate.gestureRecognizer(pan, shouldReceive: UITouch(nested)), "Controls and editable text must retain their own gestures")
    }
    let carousel = UIScrollView(); carousel.superview = list
    carousel.contentSize.width = 780
    expect(!delegate.gestureRecognizer(pan, shouldReceive: UITouch(carousel)), "Horizontal scrolling must not navigate to chats")
    carousel.contentSize.width = 390; carousel.alwaysBounceHorizontal = true
    expect(!delegate.gestureRecognizer(pan, shouldReceive: UITouch(carousel)), "A horizontally bouncing control must retain its gesture")
    let verticalPan = UIGestureRecognizer(); verticalPan.view = list
    expect(delegate.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: verticalPan), "Vertical list scrolling can recognize simultaneously")
    let horizontalPan = UIGestureRecognizer(); horizontalPan.view = carousel
    expect(!delegate.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: horizontalPan), "Horizontal controls must not recognize together")
    expect(!RGHiddenTabBarPolicy.shouldBeginBackGesture(distanceX: .nan, distanceY: 0, velocityX: 1, velocityY: 0), "Reject non-finite input")
    print("Production full-width settings gesture passed: direction, root gating, controls, nested horizontal views and vertical scrolling.")
} }
'''.replace('DELEGATE', delegate)
ui = '''
import UIKit
protocol TelegramRootControllerInterface: AnyObject { func openChats() }
protocol TabBarController: UIViewController {
    func rgBeginInteractiveReturnToChats() -> Bool
    func rgUpdateInteractiveReturnToChats(progress: CGFloat)
    func rgEndInteractiveReturnToChats(completed: Bool, velocity: CGFloat)
}
final class Window { var viewController: UIViewController? }
final class Shared { var mainWindow: Window? }
final class Context { let sharedContext = Shared() }
DELEGATE
final class Controller: UIViewController {
    private var rgRootBackGestureDelegate: RGRootSettingsBackGestureDelegate?
    private var rgRootBackGesture: UIPanGestureRecognizer?
    private weak var rgRootBackTabs: TabBarController?
    ATTACH
    var rgCanReturnToChats = false
    var isSettings = true
    let context = Context()
    HANDLER
    func install() {
        REGISTRATION
    }
}
'''.replace('DELEGATE', delegate).replace('HANDLER', handler).replace('ATTACH', attach).replace('REGISTRATION', registration)
with tempfile.TemporaryDirectory(prefix='regram-settings-pan-checks-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    (folder / 'UIKitCheck.swift').write_text(ui)
    policy = str(root / 'Regram/RGSimpleSettings/Sources/RGHiddenTabBarPolicy.swift')
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', policy,
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], check=True)
    subprocess.run([str(folder / 'tests')], check=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '5',
                    '-warnings-as-errors', '-target', 'arm64-apple-ios15.0-simulator', '-sdk', sdk,
                    policy, str(folder / 'UIKitCheck.swift')], check=True)
    print('Production delegate, selector and full-width recognizer registration passed real UIKit SDK typechecking.')

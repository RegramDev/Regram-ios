#!/usr/bin/env python3
"""Exercise the production row button's tracking cancellation and typecheck it against UIKit."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenSelectableBackgroundNode.swift').read_text()
button = source[source.index('final class PeerInfoScreenSelectableButton:'):source.index('\nfinal class PeerInfoScreenSelectableBackgroundNode:')]
assert 'self.button = PeerInfoScreenSelectableButton()' in source
fixture = r'''
import Foundation
import CoreGraphics
class UIEvent {}
class UITouch {
    var point: CGPoint
    init(_ x: CGFloat, _ y: CGFloat) { point = CGPoint(x: x, y: y) }
    func location(in button: HighlightTrackingButton) -> CGPoint { point }
}
class HighlightTrackingButton {
    var highlighted = false
    func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { highlighted = true; return true }
    func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { true }
    func cancelTracking(with event: UIEvent?) { highlighted = false }
}
BUTTON
@main enum Checks {
    static func main() {
        let button = PeerInfoScreenSelectableButton()
        let touch = UITouch(120, 22)
        precondition(button.beginTracking(touch, with: nil))
        touch.point.x += 3
        precondition(button.continueTracking(touch, with: nil) && button.highlighted, "Normal tap jitter stays clickable")
        for offset in [CGPoint(x: 11, y: 0), CGPoint(x: -60, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: 8, y: 8)] {
            touch.point = CGPoint(x: 120, y: 22)
            precondition(button.beginTracking(touch, with: nil))
            touch.point.x += offset.x; touch.point.y += offset.y
            precondition(!button.continueTracking(touch, with: nil) && !button.highlighted, "A swipe must stop tracking and clear the pending row tap")
        }
        touch.point = CGPoint(x: 120, y: 22)
        precondition(button.beginTracking(touch, with: nil) && button.continueTracking(touch, with: nil), "The next tap works after cancellation")
        print("Settings row tracking passed: tap jitter, horizontal/vertical/diagonal swipes, highlight cancellation and subsequent taps.")
    }
}
'''.replace('BUTTON', button)
with tempfile.TemporaryDirectory(prefix='regram-settings-row-') as directory:
    work = Path(directory)
    swift = work / 'Checks.swift'
    swift.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True)
    ui = work / 'UIKit.swift'
    ui.write_text('import UIKit\n' + button)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios15.0', '-sdk', sdk, str(root / 'submodules/Display/Source/HighlightTrackingButton.swift'), str(ui)], check=True)
    print('Production row button passed real arm64 UIKit SDK typechecking.')

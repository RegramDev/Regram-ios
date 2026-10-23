import XCTest
import UIKit
import AsyncDisplayKit
import Display
import ComponentFlow
@testable import NavigationBarComponent

private final class ButtonTouch: UITouch {
    let target: UIView
    var point: CGPoint

    init(target: UIView, point: CGPoint) {
        self.target = target
        self.point = point
        super.init()
    }

    override var view: UIView? { self.target }
    override var tapCount: Int { 1 }
    override func location(in view: UIView?) -> CGPoint {
        return self.target.convert(self.point, to: view)
    }
}

final class RGSettingsLeadingButtonsTests: XCTestCase {
    private func host(_ node: RGSettingsLeadingButtonsNode) -> UIView {
        let component = ComponentView<NavigationButtonEnvironment>()
        let theme = NavigationBarTheme(overallDarkAppearance: false, buttonColor: .black, disabledButtonColor: .gray, primaryTextColor: .black, badgeBackgroundColor: .red, badgeTextColor: .white, accentButtonColor: .blue, accentDisabledButtonColor: .gray, accentForegroundColor: .white)
        let size = component.update(
            transition: .immediate,
            component: AnyComponent(NavigationButtonComponent(content: .node(node), color: .black, isEnabled: true, pressed: { _ in
                XCTFail("The navigation wrapper must leave actions to the two child buttons")
            }, contextAction: nil)),
            environment: { NavigationButtonEnvironment(theme: theme) },
            containerSize: CGSize(width: 200.0, height: 44.0)
        )
        let view = component.view!
        view.frame = CGRect(origin: .zero, size: size)
        XCTAssertEqual(size, CGSize(width: 88.0, height: 44.0))
        return view
    }

    private func button(at point: CGPoint, in host: UIView, node: RGSettingsLeadingButtonsNode) throws -> HighlightableButtonNode {
        let hit = try XCTUnwrap(host.hitTest(point, with: nil))
        return try XCTUnwrap(node.subnodes?.compactMap { $0 as? HighlightableButtonNode }.first { $0.view === hit }, "Touch must reach a child button, not the inert navigation wrapper")
    }

    private func tap(at point: CGPoint, in host: UIView, node: RGSettingsLeadingButtonsNode, cancel: Bool = false) throws {
        let button = try self.button(at: point, in: host, node: node)
        let touch = ButtonTouch(target: button.view, point: host.convert(point, to: button.view))
        button.touchesBegan([touch], with: nil)
        if cancel {
            button.touchesCancelled([touch], with: nil)
        }
        button.touchesEnded([touch], with: nil)
    }

    func test_backAndQRAreIndependentTapTargets() throws {
        let node = RGSettingsLeadingButtonsNode()
        let host = self.host(node)
        var back = 0, qr = 0
        node.back = { back += 1 }
        node.openQR = { qr += 1 }
        try self.tap(at: CGPoint(x: 22.0, y: 22.0), in: host, node: node)
        XCTAssertEqual(back, 1)
        XCTAssertEqual(qr, 0)
        try self.tap(at: CGPoint(x: 66.0, y: 22.0), in: host, node: node)
        XCTAssertEqual(back, 1)
        XCTAssertEqual(qr, 1)
    }

    func test_entire44PointTargetsAndAccessibilitySurviveThemeUpdates() throws {
        let node = RGSettingsLeadingButtonsNode()
        let host = self.host(node)
        for color in [UIColor.white, .black, .white] {
            node.update(backImage: nil, qrImage: nil, color: color, backTitle: "返回", qrTitle: "二维码")
            XCTAssertFalse(node.isAccessibilityElement)
            for (x, title) in [(CGFloat(1), "返回"), (43, "返回"), (44, "二维码"), (87, "二维码")] {
                for y in [CGFloat(1), 43] {
                    let button = try self.button(at: CGPoint(x: x, y: y), in: host, node: node)
                    XCTAssertEqual(button.accessibilityLabel, title)
                    XCTAssertTrue(button.isAccessibilityElement)
                    XCTAssertTrue(button.accessibilityTraits.contains(.button))
                }
            }
        }
        XCTAssertNil(host.hitTest(CGPoint(x: -1, y: 22), with: nil))
        XCTAssertNil(host.hitTest(CGPoint(x: 89, y: 22), with: nil))
    }

    func test_cancelledTouchesDoNotNavigate() throws {
        let node = RGSettingsLeadingButtonsNode()
        let host = self.host(node)
        var actions = 0
        node.back = { actions += 1 }
        node.openQR = { actions += 1 }
        for x in [CGFloat(22), 66] {
            try self.tap(at: CGPoint(x: x, y: 22), in: host, node: node, cancel: true)
        }
        XCTAssertEqual(actions, 0)
    }

    func test_returningToSettingsRehostsLiveButtons() throws {
        let node = RGSettingsLeadingButtonsNode()
        var host = self.host(node)
        var actions = 0
        node.back = { actions += 1 }
        node.openQR = { actions += 1 }
        try self.tap(at: CGPoint(x: 22, y: 22), in: host, node: node)
        node.view.removeFromSuperview()
        host = self.host(node)
        try self.tap(at: CGPoint(x: 66, y: 22), in: host, node: node)
        XCTAssertEqual(actions, 2)
    }
}

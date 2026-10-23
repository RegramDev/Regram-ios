#!/usr/bin/env python3
"""Exercise production common-group status-bar routing and short localized back items."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
source = (root / 'Regram/RGCommonGroupMessagesUI/Sources/RGCommonGroupMessagesController.swift').read_text()
a = source.index('private func rgConfigureCommonGroupTableNavigation(')
b = source.index('\nprivate final class GroupSearch', a)
setup = source[a:b]
fixture = r'''
import Foundation
import CoreGraphics
struct UIEdgeInsets { var top: CGFloat = 0 }
final class UIBarButtonItem {
    enum Style { case plain }
    let title: String?
    init(title: String?, style: Style, target: Any?, action: Any?) { self.title = title }
}
final class NavigationItem { var backBarButtonItem: UIBarButtonItem? }
class ViewController {
    let navigationItem = NavigationItem()
    var scrollToTop: (() -> Void)?
    var title: String?
}
final class WeakTable { weak var value: UITableView?; init(_ value: UITableView) { self.value = value } }
class UITableView {
    var scrollsToTop = true
    var adjustedContentInset = UIEdgeInsets()
    var contentOffset = CGPoint(x: 5, y: 1800)
    var animated = false
    func setContentOffset(_ point: CGPoint, animated: Bool) { contentOffset = point; self.animated = animated }
}
SETUP
@main enum Checks {
    static func main() {
        for label in ["返回", "Back", "返回"] {
            let controller = ViewController(), table = UITableView()
            controller.title = String(repeating: "Long display name ", count: 30)
            let originalTitle = controller.title
            rgConfigureCommonGroupTableNavigation(controller: controller, table: table, backTitle: label)
            precondition(controller.navigationItem.backBarButtonItem?.title == label && controller.title == originalTitle, "Keep the page title and use a short localized back title on the next page")
            precondition(!table.scrollsToTop && controller.scrollToTop != nil, "Only the application's status-bar proxy should receive the system gesture")
            table.adjustedContentInset.top = 44
            controller.scrollToTop?()
            precondition(table.contentOffset == CGPoint(x: 5, y: -44) && table.animated, "Return to the first content position with its adjusted top inset")
            table.adjustedContentInset.top = 0; table.contentOffset.y = -30
            controller.scrollToTop?()
            precondition(table.contentOffset == CGPoint(x: 5, y: 0), "Empty, short and overscrolled lists have no row-index dependency")
        }
        let controller = ViewController()
        var table: UITableView? = UITableView(); let released = WeakTable(table!)
        rgConfigureCommonGroupTableNavigation(controller: controller, table: table!, backTitle: "Back")
        table = nil
        precondition(released.value == nil, "The callback must not retain a dismissed table")
        controller.scrollToTop?()
        print("Common-group table navigation passed: app-proxy routing, localized short back text, unchanged long page title, insets, empty lists and weak capture.")
    }
}
'''.replace('SETUP', setup)
with tempfile.TemporaryDirectory(prefix='regram-table-navigation-') as directory:
    work = Path(directory); swift = work/'Checks.swift'; swift.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work/'checks')], check=True)
    subprocess.run([str(work/'checks')], check=True)
    ui = work/'TableNavigationSDKCheck.swift'
    ui.write_text('import UIKit\nclass ViewController: UIViewController { var scrollToTop: (() -> Void)? }\n' + setup)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios15.0', '-sdk', sdk, str(ui)], check=True)
    print('Common-group table setup passed real arm64 UIKit SDK typechecking.')

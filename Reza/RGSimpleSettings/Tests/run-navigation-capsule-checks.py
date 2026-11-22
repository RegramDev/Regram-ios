#!/usr/bin/env python3
"""Run the production capsule grouping functions and their upstream test bodies with value-only UI adapters."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'submodules/TelegramUI/Components/NavigationBarComponent'

def function(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    # Test helper signatures contain a default action closure before their body.
    if signature.startswith('private func button('):
        opening = text.index('{', text.index('-> NavigationBarComponent.Button', start))
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

layout = (BASE / 'Sources/NavigationBarRowLayout.swift').read_text()
production = '\n'.join(function(layout, f'func {name}(') for name in [
    'navigationBarButtonRequiresOwnSection', 'navigationBarRightSections'
])
tests = (BASE / 'Tests/NavigationBarRowLayoutTests.swift').read_text()
names = re.findall(r'func (test_rightSections_\w+)\(', tests)
methods = '\n'.join(function(tests, f'private func {name}(') for name in ['button', 'accent', 'sectionIds'])
methods += '\n' + '\n'.join(function(tests, f'func {name}(') for name in names)
adapters = r'''
import Foundation
final class UIView {}
final class UIImage {}
final class ASDisplayNode {}
struct TestButtonContentComponent {}
struct AnyComponent { init<T>(_ value: T) {} }
enum NavigationBarComponent {
    struct OverflowInfo { init(title: String, iconName: String?, priority: Int?) {} }
    struct Button {
        enum Content {
            case text(title: String, isBold: Bool), icon(imageName: String), image(UIImage)
            case node(ASDisplayNode), custom(AnyComponent), more
        }
        enum Tint { case generic, accent, accentDisabled }
        let id: AnyHashable, content: Content, tint: Tint, requiresOwnSection: Bool
        init(id: AnyHashable, content: Content, tint: Tint = .generic,
             requiresOwnSection: Bool = false, overflow: OverflowInfo? = nil,
             action: @escaping (UIView) -> Void) {
            self.id = id; self.content = content; self.tint = tint
            self.requiresOwnSection = requiresOwnSection
        }
    }
}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "\(lhs) != \(rhs)") }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
'''
program = adapters + '\n' + production + '\nfinal class Checks {\n' + methods + '\n}\n'
program += '@main enum Main { static func main() { let checks = Checks()\n'
program += '\n'.join(f'checks.{name}()' for name in names)
program += f'\nprint("Navigation capsule checks passed: {len(names)} production test cases") }} }}\n'
with tempfile.TemporaryDirectory(prefix='regram-navigation-capsules-') as directory:
    work = Path(directory)
    swift, binary = work / 'Checks.swift', work / 'checks'
    swift.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(swift), '-o', str(binary)], cwd=ROOT, check=True)
    subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=10)

"""Run the production tab-bar restoration block with effect-view lifecycle adapters."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
relative = 'submodules/TabBarUI/Sources/TabBarContollerNode.swift'
source = subprocess.check_output(['git', 'show', 'HEAD:' + relative], cwd=root, text=True) if args.baseline else (root / relative).read_text()
field = next(line.strip().removeprefix('private ') for line in source.splitlines() if 'private var tabBarContentState:' in line)
a = source.index('        let tabBarSearchState: ViewController.TabBarSearchState? =')
b = source.index('\n        var tabBarTransition =', a)
block = source[a:b]
fixture = '''
import Foundation
struct Empty {}
final class EffectView {
    var removed = false
    func removeFromSuperview() { removed = true }
}
final class ComponentView<T> { let view: EffectView? = EffectView() }
final class ViewController {
    struct TabBarSearchState { let isActive: Bool }
    var tabBarSearchState: TabBarSearchState?
}
struct Params { let isTabBarHidden: Bool; let toolbar: Int? }
final class Host {
    var tabBarView = ComponentView<Empty>()
    var currentController: ViewController? = ViewController()
    var needsTabBarRecreation = false
    FIELD
    func update(items: Int = 2, external: Bool = false, hidden: Bool = false, toolbar: Bool = false, searchActive: Bool = false) {
        let visibleComponentItems = Array(repeating: 0, count: items)
        let externalComponentItem: Int? = external ? 1 : nil
        let params = Params(isTabBarHidden: hidden, toolbar: toolbar ? 1 : nil)
        _ = params
        currentController?.tabBarSearchState = .init(isActive: searchActive)
        BLOCK
    }
}
func expect(_ value: @autoclosure () -> Bool, _ description: String) {
    if !value() { print(description); exit(1) }
}
@main enum Tests {
    static func main() {
        let host = Host()
        host.update()
        let original = host.tabBarView
        host.update(); expect(host.tabBarView === original, "Visible relayout must keep the effect hierarchy")
        host.update(hidden: true)
        host.update(hidden: true)
        expect(host.tabBarView === original, "Search must not rebuild glass while hidden")
        host.update()
        expect(host.tabBarView !== original, "Restoring search must rebuild the hidden effect hierarchy")
        expect(original.view!.removed, "The old glass hierarchy must be detached")
        let restored = host.tabBarView
        host.update(); expect(host.tabBarView === restored, "Restore must happen once")
        host.update(toolbar: true); host.update()
        expect(host.tabBarView !== restored, "Leaving an overlay toolbar must restore fresh glass")
        let afterToolbar = host.tabBarView
        host.update(items: 0, hidden: true)
        host.update(items: 2, hidden: true)
        expect(host.tabBarView === afterToolbar, "Global hide must defer recreation until visible")
        host.update(searchActive: true)
        expect(host.tabBarView === afterToolbar && host.needsTabBarRecreation, "An active native search must defer a pending restore")
        host.update()
        expect(host.tabBarView !== afterToolbar && !host.needsTabBarRecreation, "Search completion must consume the pending restore")
        let externalHost = Host()
        externalHost.update(items: 0)
        let empty = externalHost.tabBarView
        externalHost.update(items: 0, external: true)
        expect(externalHost.tabBarView !== empty, "A restored standalone tab must get fresh glass")
        let combined = Host()
        combined.update(); let initial = combined.tabBarView
        combined.update(hidden: true, toolbar: true)
        combined.update(hidden: true)
        expect(combined.tabBarView === initial, "Removing a toolbar must not expose globally hidden tabs")
        combined.update(); expect(combined.tabBarView !== initial, "Restoring visibility after combined hides must refresh glass")
        print("Production tab-bar restoration passed: search, toolbar, global hide, deferred search, standalone tabs and stable relayout.")
    }
}
'''.replace('FIELD', field).replace('BLOCK', block)
with tempfile.TemporaryDirectory(prefix='regram-tab-search-checks-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                    str(root / 'Regram/RGSimpleSettings/Sources/RGHiddenTabBarPolicy.swift'),
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], check=True)
    result = subprocess.run([str(folder / 'tests')], capture_output=True, text=True)
    if args.baseline:
        if result.returncode == 0 or 'Restoring search must rebuild' not in result.stdout:
            raise SystemExit('The baseline did not reproduce the intended regression: ' + result.stdout + result.stderr)
        print('Confirmed baseline regression: ' + result.stdout.strip())
    else:
        print(result.stdout, end='')
        if result.returncode:
            raise SystemExit(result.stderr or result.returncode)

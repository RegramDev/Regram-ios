"""Exercise the actual layout observer and chat cancellation guard with UI lifecycle adapters."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/TabBarUI/Sources/TabBarController.swift').read_text()
a = source.index('        self.tabBarControllerNode.rgAppearanceChanged =')
b = source.index('\n        self.updateSelectedIndex()', a)
observer = source[a:b]
chat = (root / 'submodules/ChatListUI/Sources/ChatListController.swift').read_text()
a = chat.index('    public func deactivateSearch(animated: Bool) {')
b = chat.index('        var completion:', a)
guard = chat[a:b]
fixture = '''
import Foundation
func CACurrentMediaTime() -> Double { 100 }
enum Transition { case immediate }
final class RGSimpleSettings { static let shared = RGSimpleSettings(); var bottomBarSettings = RGBottomBarSettings() }
struct SearchState { var isActive: Bool }
final class Controller {
    var tabBarSearchState: SearchState? = SearchState(isActive: true)
    var displayNavigationBar = false
    var previousSearchToggleTimestamp: Double? = 100 // A just-opened search must still cancel.
    var cancelled = 0
    var firstResponder = true
    func tabBarDeactivateSearch() { deactivateSearch(animated: true) }
    GUARD
        // Adapter for SearchDisplayController's UIKit teardown; the early-return guard is production code.
        cancelled += 1; firstResponder = false; tabBarSearchState = SearchState(isActive: false)
    }
}
final class Node { var rgAppearanceChanged: (() -> Void)? }
final class Host {
    let tabBarControllerNode = Node()
    var currentController: Controller? = Controller()
    var validLayout: Int? = 1
    var layouts = 0
    var activeAtLayout = false
    func install() { OBSERVER }
    func containerLayoutUpdated(_ layout: Int, transition: Transition) {
        layouts += 1; activeAtLayout = currentController?.tabBarSearchState?.isActive == true
    }
}
@main enum Tests {
    static func main() {
        for visible in [true, false] { for enabled in [true, false] { for active in [true, false] {
            var settings = RGBottomBarSettings(); settings.setVisible(.search, visible: enabled); settings.isBottomBarVisible = visible
            RGSimpleSettings.shared.bottomBarSettings = settings
            let host = Host(); host.currentController!.tabBarSearchState = SearchState(isActive: active); host.install()
            host.tabBarControllerNode.rgAppearanceChanged!()
            let mustClose = active && (!visible || !enabled)
            precondition(host.currentController!.cancelled == (mustClose ? 1 : 0))
            precondition(host.layouts == 1 && host.activeAtLayout == (active && !mustClose))
            if mustClose {
                precondition(!host.currentController!.firstResponder)
                host.tabBarControllerNode.rgAppearanceChanged!()
                precondition(host.currentController!.cancelled == 1)
            }
        }}}
        // A pushed result can retain the root's active search even without a currently valid layout.
        RGSimpleSettings.shared.bottomBarSettings = RGBottomBarSettings()
        let pushed = Host(); pushed.validLayout = nil; pushed.install(); pushed.tabBarControllerNode.rgAppearanceChanged!()
        precondition(pushed.currentController!.cancelled == 1 && pushed.layouts == 0)
        // Top search does not use active tab-bar state: changing the layout must not cancel it.
        let top = Host(); top.currentController!.tabBarSearchState = nil; top.install(); top.tabBarControllerNode.rgAppearanceChanged!()
        precondition(top.currentController!.cancelled == 0 && top.currentController!.firstResponder)
        // Normal native cancellation also retains its debounce while its control remains available.
        var enabledSettings = RGBottomBarSettings(); enabledSettings.setVisible(.search, visible: true)
        RGSimpleSettings.shared.bottomBarSettings = enabledSettings
        let nativeGuard = Controller(); nativeGuard.deactivateSearch(animated: true); precondition(nativeGuard.cancelled == 0)
        // Preserve the top-search debounce while bypassing it for required native teardown.
        let topGuard = Controller(); topGuard.tabBarSearchState = SearchState(isActive: false)
        topGuard.deactivateSearch(animated: true); precondition(topGuard.cancelled == 0)
        topGuard.previousSearchToggleTimestamp = 99; topGuard.deactivateSearch(animated: true); precondition(topGuard.cancelled == 1)
        print("Production search-setting teardown passed: disable search/bar, immediate cancellation, retained result state, top-search independence, stable relayout and debounce.")
    }
}
'''.replace('OBSERVER', observer).replace('GUARD', guard)
with tempfile.TemporaryDirectory(prefix='regram-search-settings-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                    str(root / 'Regram/RGSimpleSettings/Sources/RGBottomBarSettings.swift'),
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], check=True)
    subprocess.run([str(folder / 'tests')], check=True)

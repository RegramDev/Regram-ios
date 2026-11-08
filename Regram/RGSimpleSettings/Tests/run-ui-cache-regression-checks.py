#!/usr/bin/env python3
"""Run production cache subscriptions, tab-search lifecycle and album host decisions with isolated boundaries."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', help='Read the account and tab component from this Git revision')
parser.add_argument('--only-search', action='store_true', help='Reproduce the search lifecycle independently of cache settings')
args = parser.parse_args()

def source(path):
    if args.baseline:
        return subprocess.check_output(['git', 'show', args.baseline + ':' + path], cwd=ROOT, text=True)
    return (ROOT / path).read_text()

account = source('submodules/TelegramCore/Sources/Account/Account.swift')
end = account.index('        let _ = masterNotificationsKey(')
start = account.rfind('            let mediaBox = postbox.mediaBox', 0, end)
cache = account[start:account.index('\n        }', start)]
tabs = source('submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift')
end = tabs.index('\n            transition.setFrame(view: self.backgroundContainer,')
start = tabs.rfind('            if let search {', 0, end)
search = tabs[start:end]
cleanup = (ROOT / 'submodules/Postbox/Sources/TimeBasedCleanup.swift').read_text()
start = cleanup.index('        let scan: Signal<Never, NoError>')
end = cleanup.index('        self.scheduledScanDisposable.set(', start)
# Only the timer interval is accelerated; subscription, serial restart and cancellation stay production code.
schedule = cleanup[start:end].replace('self.sizeLimitRescanInterval', 'sizeLimitRescanInterval')
settings_ui = (ROOT / 'Regram/RGSettingsUI/Sources/RGBottomBarSettingsController.swift').read_text()
start = settings_ui.index('selected: { rawValue in')
start = settings_ui.index('{', start) + 1
start = settings_ui.index(' in', start) + 3
end, depth = start, 1
while depth:
    depth += (settings_ui[end] == '{') - (settings_ui[end] == '}')
    end += 1
visibility = settings_ui[start:end - 1]

fixture = r'''
import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ title: String) {
    checks += 1
    if !value() { print("FAIL: " + title); exit(1) }
}
func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
struct CacheStorageSettings: Equatable {
    var defaultCacheStorageTimeout: Int32 = .max
    var defaultCacheStorageLimitGigabytes: Int32 = .max
    static let defaultSettings = CacheStorageSettings()
}
enum SharedDataKeys { static let cacheStorageSettings = "cache" }
struct Entry: Equatable { let value: CacheStorageSettings; func get<T>(_ type: T.Type) -> T? { value as? T } }
struct SharedData: Equatable { var entries: [String: Entry] }
final class Manager {
    let values = ValuePromise<SharedData>(SharedData(entries: [:]))
    func sharedData(keys: [String]) -> Signal<SharedData, NoError> { values.get() }
    func set(_ limit: Int32) { values.set(SharedData(entries: ["cache": Entry(value: CacheStorageSettings(defaultCacheStorageLimitGigabytes: limit))])) }
}
final class MediaBox {
    var limits: [Int32] = []
    func setMaxStoreTimes(general: Int32, shortLived: Int32, gigabytesLimit: Int32) { limits.append(gigabytesLimit) }
}
final class Postbox { let mediaBox = MediaBox() }
final class AccountHost {
    let postbox = Postbox()
    let accountManager: Manager
    let managedOperationsDisposable = DisposableSet()
    init(_ manager: Manager) { accountManager = manager }
    func install() { CACHE }
    deinit { managedOperationsDisposable.dispose() }
}

class View {
    var frame = CGRect()
    var bounds: CGRect { CGRect(origin: CGPoint(), size: frame.size) }
    weak var parent: View?
    var children: [View] = []
    func addSubview(_ view: View) { view.removeFromSuperview(); children.append(view); view.parent = self }
    func removeFromSuperview() { parent?.children.removeAll { $0 === self }; parent = nil }
}
final class NavigationSearchView: View {
    init(action: @escaping () -> Void, closeAction: @escaping () -> Void) {}
    func update(size: CGSize, theme: Int, strings: Int, isActive: Bool, transition: Transition) {}
}
final class Background { let contentView = View() }
enum Axis { case horizontal, vertical }
final class Search { var isActive = false; func activate() {}; func deactivate() {} }
struct Component { var search: Search?; let theme = 0; let strings = 0; let isCompact = false; let axis = Axis.horizontal }
final class Transition {
    enum Animation { case none }
    var completions: [ObjectIdentifier: (Bool) -> Void] = [:]
    func withAnimation(_ animation: Animation) -> Transition { self }
    func setFrame(view: View, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        completions.removeValue(forKey: ObjectIdentifier(view))?(false)
        view.frame = frame
        if let completion { completions[ObjectIdentifier(view)] = completion }
    }
    func finish(_ completed: Bool) {
        let pending = Array(completions.values); completions.removeAll()
        for callback in pending { callback(completed) }
    }
}
func tabBarSearchButtonOrigin(tabsLength: CGFloat, availableLength: CGFloat, buttonLength: CGFloat, isCompact: Bool) -> CGFloat { availableLength - buttonLength }
final class SearchHost {
    var component: Component?
    var searchView: NavigationSearchView?
    let backgroundContainer = Background()
    let transition = Transition()
    func update(_ enabled: Bool, active: Bool = false) {
        let control = enabled ? Search() : nil; control?.isActive = active
        let component = Component(search: control); self.component = component
        let search = component.search
        var size = CGSize(width: 300, height: 64)
        let availableSize = CGSize(width: 300, height: 100)
        let barHeight: CGFloat = 64, tabsSize = CGSize(width: 228, height: 64)
        SEARCH
    }
}
final class VisibilityArguments {
    var settings = RGBottomBarSettings()
    func update(_ f: (inout RGBottomBarSettings) -> Void) { f(&settings) }
}
final class VisibilityHost {
    let arguments = VisibilityArguments()
    func press(_ rawValue: String) { VISIBILITY }
}
func scanSignal(limit gigabytesLimit: Int32, onScan: @escaping () -> Void) -> Signal<Never, NoError> {
    let scanQueue = Queue.mainQueue()
    let sizeLimitRescanInterval = 0.02
    let scanFirstTime = Signal<Never, NoError> { subscriber in onScan(); subscriber.putCompletion(); return EmptyDisposable }
    SCHEDULE
    return scan
}

@main enum Tests {
    static func main() {
        let manager = Manager()
        var account: AccountHost? = AccountHost(manager)
        account!.install()
        let media = account!.postbox.mediaBox
        check(media.limits == [.max], "Initial cache setting is applied")
        manager.set(4); manager.set(4); manager.set(1); manager.set(.max)
        check(media.limits == [.max, 4, 1, .max], "Running accounts apply changed limits and suppress duplicates")
        var second: AccountHost? = AccountHost(manager); second!.install()
        let secondMedia = second!.postbox.mediaBox
        manager.set(2)
        check(media.limits.last == 2 && secondMedia.limits.last == 2, "All active accounts receive the shared limit")
        account = nil; second = nil
        manager.set(8)
        check(media.limits.last == 2 && secondMedia.limits.last == 2, "Account teardown disposes the limit listener")

        let host = SearchHost()
        host.update(true)
        let first = host.searchView!
        for index in 0..<30 {
            host.update(false)
            host.update(true, active: index % 2 == 0)
            host.transition.finish(index % 2 != 0)
            check(host.backgroundContainer.contentView.children.count == 1, "Rapid search toggles leave one control")
            check(host.searchView === first, "An outgoing search control is reused")
        }
        host.update(false); host.transition.finish(false)
        check(host.searchView == nil && host.backgroundContainer.contentView.children.isEmpty, "Cancelled removal still cleans a disabled control")
        host.update(true); host.update(false); host.transition.finish(true)
        check(host.backgroundContainer.contentView.children.isEmpty, "Completed removal cleans a disabled control")

        var scans = 0
        let disposable = scanSignal(limit: 1, onScan: { scans += 1 }).start()
        pump(0.09)
        check(scans >= 3, "A finite cap is rescanned after completed scans")
        disposable.dispose(); let stopped = scans; pump(0.05)
        check(scans == stopped, "Changing limits or teardown cancels the pending rescan")
        var unlimitedScans = 0
        let unlimited = scanSignal(limit: .max, onScan: { unlimitedScans += 1 }).start()
        pump(0.06); unlimited.dispose()
        check(unlimitedScans == 1, "An unlimited cache does not schedule size rescans")

        let visibility = VisibilityHost()
        for _ in 0..<20 {
            visibility.press("contacts"); visibility.press("calls")
            visibility.press("contacts"); visibility.press("calls")
            check(visibility.arguments.settings.visibleBottomItems == RGBottomBarSettings.defaultBottomItems, "Actual visibility chips restore the saved order")
        }

        let lone = chatMessageBubbleContentHost(messageStableId: 11, isAttachment: false, containerStableIds: [])
        let album = chatMessageBubbleContentHost(messageStableId: 11, isAttachment: false, containerStableIds: [10, 11])
        check(lone == .bubble && album == .messageContainer(stableId: 11), "A cached lone file moves into its album container")
        check(chatMessageBubbleContentHost(messageStableId: 11, isAttachment: true, containerStableIds: [10, 11]) == .bubble, "Album captions and comments stay in the bubble")
        check(chatMessageBubbleStaleContentContainers(existing: [10, 11], laidOut: []) == [10, 11], "Removing an album's other file drops stale containers")
        print("UI/cache regressions:", checks, "checks passed")
    }
}
'''.replace('CACHE', cache).replace('SEARCH', search).replace('SCHEDULE', schedule).replace('VISIBILITY', visibility)
if args.only_search:
    start = fixture.index('        let manager = Manager()')
    end = fixture.index('        let host = SearchHost()', start)
    fixture = fixture[:start] + fixture[end:]

with tempfile.TemporaryDirectory(prefix='regram-ui-cache-') as temporary:
    folder = Path(temporary)
    harness = folder / 'Tests.swift'; harness.write_text(fixture)
    signals = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    binary = folder / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-O', *map(str, signals),
                    str(ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageBubbleContentHost.swift'),
                    str(ROOT / 'Regram/RGSimpleSettings/Sources/RGBottomBarSettings.swift'),
                    str(harness), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    print(result.stdout, end='')
    if args.baseline:
        expected = 'Rapid search toggles' if args.only_search else 'Running accounts apply changed limits'
        if result.returncode == 0 or expected not in result.stdout:
            raise SystemExit('Baseline did not reproduce the intended regression')
    elif result.returncode:
        raise SystemExit(result.stderr or result.returncode)

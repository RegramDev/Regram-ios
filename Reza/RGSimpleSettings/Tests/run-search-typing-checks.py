#!/usr/bin/env python3
"""Exercise the production global-search callback with real SwiftSignalKit scheduling."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
relative = 'submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift'
source = (subprocess.check_output(['git', 'show', 'HEAD:' + relative], cwd=ROOT, text=True)
          if args.baseline else (ROOT / relative).read_text())
start = source.index('    override public func searchTextUpdated(text: String) {')
end = source.index('\n    private func currentPaneUpdated', start)
callback = source[start:end].replace('override public func', 'func')
dates = (ROOT / 'submodules/ChatListUI/Sources/DateSuggestion.swift').read_text()
dates = dates.replace('import TelegramPresentationData\n', '').replace('import TelegramStringFormatting\n', '')
dates = dates.replace('func suggestDates(', 'func productionSuggestDates(')
fields = sorted(set(re.findall(r'strings\.([A-Za-z_]+)', dates)))
strings = '\n'.join(f'    let {field} = "{field.split("_")[-1]}"' for field in fields)

fixture = r'''
import Foundation

struct PresentationStrings {
STRINGS
}
struct PresentationDateTimeFormat { let dateSeparator = "." }
func stringForMonth(strings: PresentationStrings, month: Int32, ofYear: Int32) -> String { "month" }
struct PresentationData {
    let strings = PresentationStrings()
    let dateTimeFormat = PresentationDateTimeFormat()
}
enum PaneKey { case publicPosts, chats }
final class PaneContainer {
    var currentPaneKey = PaneKey.chats
    func requestSelectPane(_ key: PaneKey) { currentPaneKey = key }
}
typealias Dates = [(Date?, Date, String?)]
final class ParseTracking {
    let lock = NSLock()
    var calls: [(String, Bool)] = []
    let blocked = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func record(_ text: String) {
        lock.lock(); calls.append((text, Thread.isMainThread)); lock.unlock()
    }
    func snapshot() -> [(String, Bool)] {
        lock.lock(); defer { lock.unlock() }; return calls
    }
}
let tracking = ParseTracking()
func suggestDates(for text: String, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat) -> Dates {
    tracking.record(text)
    if text == "blocked1" {
        tracking.blocked.signal()
        _ = tracking.release.wait(timeout: .now() + 3.0)
    }
    return productionSuggestDates(for: text, strings: strings, dateTimeFormat: dateTimeFormat)
}
final class Host {
    let paneContainerNode = PaneContainer()
    let presentationData = PresentationData()
    var searchQueryValue: String?
    let searchQuery = Promise<String?>(nil)
    let suggestedDates = Promise<Dates>([])
    var queries: [String?] = []
    var dateResults: [Dates] = []
    var observers: [Disposable] = []
    init() {
        observers.append(searchQuery.get().start(next: { [weak self] query in
            precondition(Thread.isMainThread, "Queries must reach UI on main")
            self?.queries.append(query)
        }))
        observers.append(suggestedDates.get().start(next: { [weak self] dates in
            precondition(Thread.isMainThread, "Dates must reach UI on main")
            self?.dateResults.append(dates)
        }))
    }
    deinit { for observer in observers { observer.dispose() } }
CALLBACK
}

@main enum Tests {
    static func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.005)))
        }
    }
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            if !value { print("FAIL:", message); exit(1) }
        }

        let host = Host()
        let burst = ["t", "te", "tel", "tele", "teleg", "telegr", "telegra", "telegram1"]
        for text in burst { host.searchTextUpdated(text: text); pump(0.025) }
        check(host.queries.count == 1, "Rapid typing must not start intermediate queries")
        check(tracking.snapshot().isEmpty, "Rapid typing must not parse intermediate dates")
        check(host.searchQueryValue == burst.last, "Token actions see the latest text immediately")
        pump(0.25)
        check(host.queries.count == 2 && host.queries.last! == burst.last, "Only the final query starts")
        check(tracking.snapshot().map { $0.0 } == [burst.last!], "Only final text is date-parsed")
        check(tracking.snapshot().allSatisfy { !$0.1 }, "Date parsing must run off main")

        let queryCount = host.queries.count, dateCount = host.dateResults.count
        host.searchTextUpdated(text: "telegram1"); pump(0.2)
        check(host.queries.count == queryCount && host.dateResults.count == dateCount, "Duplicate text does no work")

        host.searchTextUpdated(text: "pending1"); pump(0.025)
        host.searchTextUpdated(text: "")
        check(host.queries.last! == nil && host.dateResults.last!.isEmpty, "Clearing restores recent results immediately")
        let afterClear = host.queries.count
        pump(0.25)
        check(host.queries.count == afterClear, "Cleared pending query cannot return")
        check(!tracking.snapshot().contains { $0.0 == "pending1" }, "Clearing cancels pending date parsing")

        host.searchTextUpdated(text: "slow1"); pump(0.25)
        check(host.queries.last! == "slow1", "Slow typing still searches each settled input")
        host.searchTextUpdated(text: "slow12"); pump(0.25)
        check(host.queries.last! == "slow12", "Later slow input is not dropped")

        host.paneContainerNode.currentPaneKey = .publicPosts
        host.searchTextUpdated(text: "#话题"); pump(0.25)
        check(host.paneContainerNode.currentPaneKey == .publicPosts, "Hashtag keeps public-post pane")
        host.searchTextUpdated(text: "中文 café 👩🏽‍💻")
        check(host.paneContainerNode.currentPaneKey == .chats, "Non-hashtag switches pane immediately")
        pump(0.25)
        check(host.queries.last! == "中文 café 👩🏽‍💻", "Unicode query is preserved verbatim")

        host.searchTextUpdated(text: "blocked1"); pump(0.18)
        check(tracking.blocked.wait(timeout: .now() + 1.0) == .success, "Old parser started in background")
        host.searchTextUpdated(text: "Today"); pump(0.25)
        check(host.queries.last! == "Today" && host.dateResults.last!.count == 1, "A newer query can finish during old parsing")
        let beforeStale = host.dateResults.count
        tracking.release.signal(); pump(0.2)
        check(host.dateResults.count == beforeStale, "Late old date result cannot replace the newest result")

        host.searchTextUpdated(text: "blocked1"); pump(0.18)
        check(tracking.blocked.wait(timeout: .now() + 1.0) == .success, "Parser started before clear")
        host.searchTextUpdated(text: "")
        let clearedDates = host.dateResults.count
        tracking.release.signal(); pump(0.2)
        check(host.queries.last! == nil && host.dateResults.count == clearedDates, "Clear also discards already-running date parsing")

        host.searchTextUpdated(text: "retype"); pump(0.025)
        host.searchTextUpdated(text: "")
        host.searchTextUpdated(text: "retype"); pump(0.25)
        check(host.queries.last! == "retype", "Same query after clear still runs")

        var temporary: Host? = Host()
        weak var released = temporary
        temporary!.searchTextUpdated(text: "destroyed1")
        temporary = nil; pump(0.25)
        check(released == nil, "Pending search does not retain its node")
        released = nil
        check(!tracking.snapshot().contains { $0.0 == "destroyed1" }, "Node destruction cancels pending parser")
        print("Global search typing:", checks, "checks passed;", burst.count, "rapid edits -> 1 query and 1 background date parse")
    }
}
'''.replace('STRINGS', strings).replace('CALLBACK', callback)

with tempfile.TemporaryDirectory(prefix='regram-search-typing-') as temp:
    directory = Path(temp)
    production = directory / 'DateSuggestion.swift'
    production.write_text(dates)
    harness = directory / 'SearchTyping.swift'
    harness.write_text(fixture)
    signal_sources = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-O',
                    *map(str, signal_sources), str(production), str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)

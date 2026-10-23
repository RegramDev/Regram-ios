#!/usr/bin/env python3
"""Exercise the production history-completion/read-gate callbacks with both range deduplicators."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true', help='Prove the regression against the pre-sync implementation.')
args = parser.parse_args()

def source(path):
    if args.baseline:
        return subprocess.check_output(['git', 'show', f'HEAD:{path}'], cwd=ROOT, text=True)
    return (ROOT / path).read_text()

history = source('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
completion = history[history.index('                strongSelf.historyView = transition.historyView'):]
completion = completion[:completion.index('                let loadState:')]
gate_start = history.index('                    if value', history.index('self.canReadHistoryDisposable ='))
gate = history[gate_start:history.index('                    strongSelf.controllerInteraction.canReadHistory', gate_start)]

def method(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end].replace('public func', 'func')

backends = [
    ('Legacy', 'submodules/Display/Source/ListView.swift', 'public func updateVisibleItemRange('),
    ('CoreList', 'submodules/TelegramUI/Sources/CoreListChatHistoryBackend.swift', 'func updateVisibleItemRange('),
]
for name, path, signature in backends:
    update = method(source(path), signature)
    program = r'''
import Foundation
typealias ListViewDisplayedItemRange = Int
final class Settings { var mediaLoadingExperiment = false }
enum RGSimpleSettings { static let shared = Settings() }
final class Backend {
    var range = 0
    var displayedItemRange = 0
    var internalDisplayedItemRange: Int?
    var opaqueTransactionState: Any?
    var displayedItemRangeChanged: (Int, Any?) -> Void = { _, _ in }
    func immediateDisplayedItemRange() -> Int { range }
    UPDATE
}
struct Transition { let historyView: Int }
final class History {
    var historyView = 0
    var canRead = true
    var processed: [(range: Int, version: Int)] = []
    let listView = Backend()
    init() {
        listView.displayedItemRangeChanged = { [weak self] range, state in
            guard let self, self.canRead, let version = state as? Int else { return }
            self.processed.append((range, version))
        }
    }
    func rgScheduleInlinePlaybackUpdate() {}
    func complete(version: Int) {
        let strongSelf = self, transition = Transition(historyView: version)
        // Backends normally notify only when geometry changes. Publish the new history first,
        // as chatHistoryTransaction does, then invoke the actual production completion statements.
        listView.opaqueTransactionState = version
        listView.updateVisibleItemRange(force: false)
        COMPLETE
    }
    func setReadable(_ value: Bool) {
        canRead = value
        let strongSelf = self
        GATE
    }
}
@main enum Checks {
    static func main() {
        let history = History()
        history.complete(version: 1)
        history.processed.removeAll()
        history.complete(version: 2)
        precondition(history.processed.contains { $0.version == 2 && $0.range == 0 },
                     "Updated mentions in unchanged visible rows must be processed without the 10-second timer")
        history.processed.removeAll()
        history.setReadable(false)
        history.complete(version: 3)
        precondition(history.processed.isEmpty, "A background/covered chat must not read messages")
        history.setReadable(true)
        precondition(history.processed.contains { $0.version == 3 && $0.range == 0 },
                     "Reopening the read gate must process the current rows with media experiment disabled")
        history.processed.removeAll()
        history.listView.updateVisibleItemRange(force: false)
        precondition(history.processed.isEmpty, "Ordinary unchanged scroll callbacks remain deduplicated")
        history.listView.range = 1
        history.listView.updateVisibleItemRange(force: false)
        precondition(history.processed.count == 1 && history.processed[0].range == 1,
                     "A real viewport change still processes its own range")
        print("NAME visible-read checks passed: history updates, read gating and unchanged/changed viewport callbacks")
    }
}
'''
    for key, value in [('UPDATE', update), ('COMPLETE', completion), ('GATE', gate), ('NAME', name)]:
        program = program.replace(key, value)
    with tempfile.TemporaryDirectory(prefix='regram-visible-read-') as directory:
        work = Path(directory)
        swift = work / 'Checks.swift'
        swift.write_text(program)
        binary = work / 'checks'
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(swift), '-o', str(binary)], cwd=ROOT, check=True)
        subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=10)

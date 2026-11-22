#!/usr/bin/env python3
"""Exercise search transaction options and ListView's production work dispatcher."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline-ref')
args = parser.parse_args()
relative = 'submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift'
source = (subprocess.check_output(['git', 'show', args.baseline_ref + ':' + relative], cwd=ROOT, text=True)
          if args.baseline_ref else (ROOT / relative).read_text())


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


dequeue = source[source.index('    private func dequeueTransition()'):]
options = dequeue[dequeue.index('            var options ='):dequeue.index('            self.listNode?.transaction(')]
types = (ROOT / 'submodules/Display/Source/ListViewIntermediateState.swift').read_text()
option_type = block(types, 'public struct ListViewDeleteAndInsertOptions:')
list_view = (ROOT / 'submodules/Display/Source/ListView.swift').read_text()
dispatch = block(list_view, '    private func async(_ f:').replace('private func', 'func')
start = list_view.index('        if options.contains(.Synchronous) {\n            actions()')
end = list_view.index('\n    }', start)
scheduling = list_view[start:end]

fixture = r'''
import Foundation
OPTION_TYPE
enum Key { case chats, topics, channels, apps, globalPosts, media, downloads }
struct Transition { let query: String?; let animated: Bool }
final class Renderer {
    let key: Key
    var useMainQueueTransactions = false
    init(_ key: Key) { self.key = key }
    func options(query: String?, firstTime: Bool, animated: Bool) -> ListViewDeleteAndInsertOptions {
        let transition = Transition(query: query, animated: animated)
        let isFirstTime = firstTime
OPTIONS
        return options
    }
DISPATCH
    func perform(options: ListViewDeleteAndInsertOptions, actions: @escaping () -> Void) {
SCHEDULING
    }
}
@main enum Tests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            if !value { print("FAIL:", message); exit(1) }
        }
        let synchronous: ListViewDeleteAndInsertOptions = [.Synchronous, .PreferSynchronousDrawing, .PreferSynchronousResourceLoading]
        let keys: [Key] = [.chats, .topics, .channels, .apps, .globalPosts]
        for key in keys {
            let renderer = Renderer(key)
            for query in ["t", "telegram", "nihao", "群消息", "中文 English 👩🏽‍💻", " "] {
                let options = renderer.options(query: query, firstTime: true, animated: false)
                check(options.intersection(synchronous).isEmpty, "New typed queries must not force synchronous layout, drawing or resource loads")
                let done = DispatchSemaphore(value: 0)
                let result = NSLock()
                var ranOnMain = true
                renderer.perform(options: options) {
                    result.lock(); ranOnMain = Thread.isMainThread; result.unlock(); done.signal()
                }
                check(done.wait(timeout: .now() + 2.0) == .success, "Search layout completes off main")
                result.lock(); let onMain = ranOnMain; result.unlock()
                check(!onMain, "The actual ListView dispatcher must give the keyboard thread back")
            }
            for query: String? in [nil, ""] {
                check(renderer.options(query: query, firstTime: true, animated: false).isSuperset(of: synchronous), "Initial idle-state presentation retains its synchronous behavior")
            }
            check(renderer.options(query: "query", firstTime: false, animated: true).contains(.AnimateInsertion), "Selection and expansion animations are preserved")
        }
        let downloads = Renderer(.downloads).options(query: "file", firstTime: true, animated: false)
        check(downloads.contains(.PreferSynchronousDrawing) && downloads.contains(.PreferSynchronousResourceLoading), "Downloads keep their existing drawing and resource policy")
        check(!downloads.contains(.Synchronous), "Downloads do not gain synchronous layout")
        check(Renderer(.media).options(query: "media", firstTime: true, animated: false).intersection(synchronous).isEmpty, "Media remains asynchronous")
        print("Search result rendering:", checks, "checks passed with production transaction options and dispatcher")
    }
}
'''.replace('OPTION_TYPE', option_type).replace('OPTIONS', options).replace('DISPATCH', dispatch).replace('SCHEDULING', scheduling)

with tempfile.TemporaryDirectory(prefix='regram-search-rendering-') as temp:
    path = Path(temp)
    source = path / 'SearchRendering.swift'
    source.write_text(fixture)
    binary = path / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-O', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)

#!/usr/bin/env python3
"""Use the real SwiftSignalKit scheduler to check synchronous/asynchronous chunk transitions."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'Regram/RGGTranslate/Sources/RGGTranslate.swift').read_text()
a = source.index('private func rgTranslateSplitIntoChunks')
b = source.index('// MARK: - translate.googleapis.com', a)
c = source.index('public func gtranslateSplitTextBySentences')
d = source.index('private func rgTranslateSequentially', c)
production = 'import Foundation\nimport SwiftSignalKit\npublic enum TranslateFetchError: Error { case network }\nlet rgTranslateMaxChunkLength = 1200\n' + source[a:b] + source[c:d] + source[d:]
tests = r'''
import Foundation
import SwiftSignalKit
@main enum Checks {
 static func collect(_ signal: Signal<[String], TranslateFetchError>) -> (value: [String]?, failed: Bool) {
  let done = DispatchSemaphore(value: 0)
  var value: [String]?, failed = false
  let request = signal.start(next: { value = $0 }, error: { _ in failed = true; done.signal() }, completed: { done.signal() })
  precondition(done.wait(timeout: .now() + 2) == .success, "A chunk sequence stalled")
  request.dispose()
  return (value, failed)
 }
 static func delayed(_ value: String) -> Signal<String, TranslateFetchError> {
  Signal { subscriber in
   let cancelled = Atomic(value: false)
   DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
    if !cancelled.with({ $0 }) { subscriber.putNext(value); subscriber.putCompletion() }
   }
   return ActionDisposable { _ = cancelled.swap(true) }
  }
 }
 static func main() {
  let mixed = collect(rgTranslateSequentially([.single("first"), .single(""), delayed("last")], chunkTimeout: 0.2))
  precondition(mixed.value == ["first", "", "last"] && !mixed.failed)
  for limit in [1000, 1200, 2000] {
   let text = String(repeating: "a", count: limit + 1) + "\n\n" + String(repeating: "b", count: limit + 1)
   let done = DispatchSemaphore(value: 0)
   var output: String?
   let request = rgTranslateInChunks(text, "en", maxLength: limit, chunkTimeout: 0.2, { chunk, _ in delayed(chunk) }).start(next: { output = $0 }, error: { _ in fatalError("Unexpected translation failure") }, completed: { done.signal() })
   precondition(done.wait(timeout: .now() + 2) == .success && output?.filter({ $0 == "a" }).count == limit + 1 && output?.filter({ $0 == "b" }).count == limit + 1)
   request.dispose()
  }
  let timeout = collect(rgTranslateSequentially([.single(""), .never()], chunkTimeout: 0.05))
  precondition(timeout.failed && timeout.value == nil)
  let failure = collect(rgTranslateSequentially([.single(""), .fail(.network)], chunkTimeout: 0.2))
  precondition(failure.failed && failure.value == nil)
  let started = DispatchSemaphore(value: 0), cancelled = DispatchSemaphore(value: 0)
  let emitted = Atomic(value: false)
  let pending = Signal<String, TranslateFetchError> { _ in started.signal(); return ActionDisposable { cancelled.signal() } }
  let request = rgTranslateSequentially([.single(""), pending, .single("must not start")]).start(next: { _ in _ = emitted.swap(true) })
  precondition(started.wait(timeout: .now() + 1) == .success)
  request.dispose()
  precondition(cancelled.wait(timeout: .now() + 1) == .success && !emitted.with({ $0 }))
  print("Translation sequencing passed: blank separators at all chunk limits, synchronous transitions, async completion, timeout, failure and cancellation.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-chunk-sequencing-') as temporary:
    work = Path(temporary)
    files = sorted((root / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-emit-library', '-emit-module', '-module-name', 'SwiftSignalKit', *map(str, files), '-emit-module-path', str(work / 'SwiftSignalKit.swiftmodule'), '-o', str(work / 'libSwiftSignalKit.dylib')], check=True, capture_output=True)
    (work / 'Checks.swift').write_text(production + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', '-I', str(work), '-L', str(work), '-lSwiftSignalKit', '-Xlinker', '-rpath', '-Xlinker', str(work), str(work / 'Checks.swift'), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True, timeout=20)

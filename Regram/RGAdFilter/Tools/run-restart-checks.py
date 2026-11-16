#!/usr/bin/env python3
"""Exercise real bridge/store/disk-cache across process restarts with a deterministic classifier.

No accounts or network access. Stub model resources identify the test classifier only;
these timings check cache restoration, not Core ML performance.
"""
from pathlib import Path
import json
import runpy
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
bridge = runpy.run_path(str(Path(__file__).with_name('run-bridge-checks.py')))
contract = (root / 'Regram/RGAdFilter/Sources/AdSemanticClassifier.swift').read_text().split('/// A bundled, trained transformer.')[0]
adapter = r'''
final class RGAdSemanticClassifier {
    static let shared = RGAdSemanticClassifier()
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func predict(_ input: RGAdInput) -> RGAdSemanticResult {
        lock.lock(); calls += 1; lock.unlock()
        if CommandLine.arguments[1] == "corrupt" { return RGAdSemanticResult(completed: false) }
        let source = input.text as NSString, start = source.range(of: "商业推广案例").location
        if start != NSNotFound {
            return RGAdSemanticResult(predictions: [RGAdPrediction(range: RGAdRange(start, source.length), confidence: 1)], threshold: 0.99, entireMessage: start == 0)
        }
        return RGAdSemanticResult()
    }
    func reduceMemoryPressure() {}
}
'''
checks = r'''
@main enum Checks {
    static func spin(_ condition: () -> Bool) {
        let until = Date().addingTimeInterval(10)
        while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
        precondition(condition(), "restart check did not finish")
    }
    static func main() throws {
        let mode = CommandLine.arguments[1], path = CommandLine.arguments[2]
        let context = AccountContext(path), account = context.account.peerId, model = RGAdSemanticClassifier.shared
        let started = ProcessInfo.processInfo.systemUptime, session = RGAdFilterSession.get(context)
        let scope = RGAdFilterSession.Scope.historyView(UUID())
        let ad = "商业推广案例：提供专业商业服务，订购套餐享专属折扣，请联系办理。"
        let whole = Message(id: 1, text: ad, media: [TelegramMediaImage()])
        let normal = Message(id: 2, text: "这是一条正常的开源工具使用指南。")
        let mixed = Message(id: 3, text: "这是一段应该保留的正常技术介绍。\n\n" + ad, media: [TelegramMediaImage()])
        if mode == "correction" {
            var saved = false
            session.perform(changes: true, { store in
                var sample = try rgAdSampleDraft(whole, store: store)
                sample.spans = []; sample.mediaLabel = .normal
                try store.save(sample)
            }) { try! $0.get(); saved = true }
            spin { saved }
        }
        let edited = Message(id: 1, text: "编辑后的正常频道消息需要重新判断", media: [TelegramMediaImage()], version: 2)
        let messages = [mode == "edit" ? edited : whole, normal, mixed]
        var done = false
        session.prepare(messages, accountPeerId: account, scope: scope) { DispatchQueue.main.async { done = true } }
        spin { done }
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let expected = ["prime": 3, "resume": 0, "correction": 0, "edit": 1, "version": 3, "corrupt": 3][mode]!
        precondition(model.count == expected, "cache reused or recomputed the wrong inputs in \(mode): \(model.count)")
        if mode == "corrupt" {
            precondition(messages.allSatisfy { !session.isPrepared($0, accountPeerId: account, scope: scope) })
            precondition(messages.allSatisfy { session.display($0, accountPeerId: account, scope: scope) === $0 })
        } else {
            precondition(messages.allSatisfy { session.isPrepared($0, accountPeerId: account, scope: scope) })
            precondition(session.shouldHide(whole, accountPeerId: account, scope: scope) == (mode != "edit" && mode != "correction"))
            precondition(session.display(normal, accountPeerId: account, scope: scope) === normal)
            let projected = session.display(mixed, accountPeerId: account, scope: scope)
            precondition(projected.text.contains("正常技术介绍") && !projected.text.contains("商业推广案例") && projected.media.count == 1)
        }
        if mode == "correction" {
            // A reviewed attachment is bound to its original snapshot. A different snapshot
            // with the same caption still receives the cached model result, not that review.
            let other = Message(id: 4, text: ad, media: [TelegramMediaImage()])
            done = false
            session.prepare([other], accountPeerId: account, scope: .pinnedView(UUID())) { DispatchQueue.main.async { done = true } }
            spin { done }
            precondition(session.shouldHide(other, accountPeerId: account) && model.count == 0)
        }
        if mode == "prime" {
            let file = URL(fileURLWithPath: path).appendingPathComponent("regram-ad-cache-v1/verdicts.json")
            spin { FileManager.default.fileExists(atPath: file.path) }
        }
        print("\(mode): \(model.count) model calls, \(Int(elapsed)) ms to prepared results; passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-ad-restart-') as directory:
    folder = Path(directory)
    resources = folder / 'resources'
    resources.mkdir()
    manifest = {'version': 1, 'modelSHA256': 'a' * 64, 'vocabularySHA256': 'b' * 64, 'threshold': 0.99}
    (resources / 'RGAdModel.json').write_text(json.dumps(manifest))
    (resources / 'RGAdVocabulary.txt').touch()
    (resources / 'RGAdSemantic.mlmodel').touch()
    source = bridge['bridge'].replace('RGAdSemanticCache.bundledNamespace()', 'RGAdSemanticCache.bundledNamespace(resourceDirectory: URL(fileURLWithPath: CommandLine.arguments[3]))')
    (folder / 'Main.swift').write_text(bridge['adapters'] + '\n' + source + '\n' + checks)
    (folder / 'Adapter.swift').write_text(contract + adapter)
    sources = [p for p in sorted((root / 'Regram/RGAdFilter/Sources').glob('*.swift')) if p.name != 'AdSemanticClassifier.swift']
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', *map(str, sources), str(folder / 'Adapter.swift'), str(folder / 'Main.swift'), '-o', str(executable)], check=True)
    account = folder / 'account'
    def run(mode, path):
        subprocess.run([str(executable), mode, str(path), str(resources)], check=True, timeout=30)
    run('prime', account)
    run('resume', account)
    for mode in ['correction', 'edit', 'corrupt', 'version']:
        copy = folder / mode
        shutil.copytree(account, copy)
        if mode == 'corrupt':
            file = copy / 'regram-ad-cache-v1/verdicts.json'
            envelope = json.loads(file.read_text())
            envelope['checksum'] = 'damaged'
            file.write_text(json.dumps(envelope))
        if mode == 'version':
            manifest['threshold'] = 0.98
            (resources / 'RGAdModel.json').write_text(json.dumps(manifest))
        run(mode, copy)
    print('Restart checks passed; fresh processes, real bridge/store/cache, deterministic classifier.')

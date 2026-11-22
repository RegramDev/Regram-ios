#!/usr/bin/env python3
"""Check the real bridge's responsiveness while a deterministic model adapter is busy.

The deliberately slow adapter isolates queue blocking; timings are not model benchmarks.
No account or network access. Run without RG_AD_LATENCY_BASELINE for regression assertions.
"""
from pathlib import Path
import runpy
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
bridge = runpy.run_path(str(Path(__file__).with_name('run-bridge-checks.py')))
contract = (root / 'Reza/RGAdFilter/Sources/AdSemanticClassifier.swift').read_text().split('/// A bundled, trained transformer.')[0]
adapter = r'''
final class RGAdSemanticClassifier {
    static let shared = RGAdSemanticClassifier()
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var released = false
    private var predictions = 0
    var hasReleased: Bool { lock.lock(); defer { lock.unlock() }; return released }
    var count: Int { lock.lock(); defer { lock.unlock() }; return predictions }
    func predict(_ input: RGAdInput) -> RGAdSemanticResult {
        lock.lock(); predictions += 1; lock.unlock()
        if input.text == "等待中的语义消息" || input.text.contains("阻塞:") {
            lock.lock(); released = false; lock.unlock()
            entered.signal()
            precondition(resume.wait(timeout: .now() + 3) == .success, "test did not release inference")
            lock.lock(); released = true; lock.unlock()
        }
        if input.text.contains("阻塞:广告") {
            return RGAdSemanticResult(predictions: [RGAdPrediction(range: RGAdRange(0, input.text.utf16.count), confidence: 1)], threshold: 0.99, entireMessage: true)
        }
        return RGAdSemanticResult()
    }
    func reduceMemoryPressure() {}
}
'''
checks = r'''
@main enum Checks {
    static func spin(_ condition: () -> Bool) {
        let until = Date().addingTimeInterval(5)
        while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
        precondition(condition(), "responsive bridge did not finish")
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = AccountContext(root.path), session = RGAdFilterSession.get(context), account = context.account.peerId
        let model = RGAdSemanticClassifier.shared
        let slow = Message(id: 1, text: "等待中的语义消息")
        let slowScope = RGAdFilterSession.Scope.historyView(UUID())
        var slowDone = false
        session.prepare([slow], accountPeerId: account, scope: slowScope) { DispatchQueue.main.async { slowDone = true } }
        precondition(model.entered.wait(timeout: .now() + 3) == .success)
        // A finite gate lets the baseline finish as well, without deadlocking a failed check.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { model.resume.signal() }
        let ad = Message(id: 2, text: "服务套餐与购买说明\n#ad", media: [TelegramMediaImage()])
        let scope = RGAdFilterSession.Scope.pinnedView(UUID())
        var fastDone = false, earlyResult = false, notified = false, earlyNotification = false
        var resultMilliseconds = 0.0, notificationMilliseconds = 0.0
        let started = ProcessInfo.processInfo.systemUptime
        let observer = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: .main) { _ in
            if !notified, session.shouldHide(ad, accountPeerId: account, scope: scope) {
                notified = true; earlyNotification = !model.hasReleased
                notificationMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            }
        }
        session.prepare([ad], accountPeerId: account, scope: scope) {
            let early = !model.hasReleased
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            DispatchQueue.main.async { earlyResult = early; resultMilliseconds = elapsed; fastDone = true }
        }
        spin { fastDone && notified && slowDone }
        NotificationCenter.default.removeObserver(observer)
        precondition(session.shouldHide(ad, accountPeerId: account, scope: scope))
        precondition(session.display(ad, accountPeerId: account, scope: scope).media.isEmpty)
        precondition(session.isPrepared(slow, accountPeerId: account, scope: slowScope))
        print("Busy-model rule result: \(Int(resultMilliseconds)) ms; notification: \(Int(notificationMilliseconds)) ms; before model completion: result=\(earlyResult), notification=\(earlyNotification)")
        if ProcessInfo.processInfo.environment["RG_AD_LATENCY_BASELINE"] != "1" {
            precondition(earlyResult && earlyNotification, "an unrelated inference blocked an already decidable advertisement")
            try checkInvalidation(root.appendingPathComponent("invalidations"))
            try checkPartialAndReuse(root.appendingPathComponent("partial"))
        }
        print("Latency bridge checks passed; synthetic inference delay, not a device/model benchmark.")
    }

    static func checkInvalidation(_ root: URL) throws {
        let context = AccountContext(root.path), session = RGAdFilterSession.get(context), account = context.account.peerId
        let model = RGAdSemanticClassifier.shared, scope = RGAdFilterSession.Scope.historyView(UUID())
        let oversized = Message(id: 9, text: String(repeating: "正常说明", count: 17_000))
        var oversizedDone = false
        session.prepare([oversized], accountPeerId: account, scope: scope) { DispatchQueue.main.async { oversizedDone = true } }
        spin { oversizedDone }
        precondition(session.isPrepared(oversized, accountPeerId: account, scope: scope) && session.display(oversized, accountPeerId: account, scope: scope) === oversized, "unsupported input stranded a fallback instead of retaining its original")
        let old = Message(id: 10, text: "阻塞:广告，提供商业服务，欢迎联系购买套餐")
        var retired = false, editedDone = false
        session.prepare([old], accountPeerId: account, scope: scope) { DispatchQueue.main.async { retired = true } }
        precondition(model.entered.wait(timeout: .now() + 3) == .success)
        let edited = Message(id: 10, text: "这是更新后的正常使用说明", version: 2)
        session.prepare([edited], accountPeerId: account, scope: scope) { DispatchQueue.main.async { editedDone = true } }
        model.resume.signal()
        spin { retired && editedDone }
        precondition(!session.isPrepared(old, accountPeerId: account, scope: scope), "stale inference was published")
        precondition(session.isPrepared(edited, accountPeerId: account, scope: scope) && !session.shouldHide(edited, accountPeerId: account, scope: scope))

        let cancelled = Message(id: 20, text: "阻塞:广告，另一条已离开视图的套餐消息")
        var cancelledCompletion = false
        let token = session.prepare([cancelled], accountPeerId: account, scope: scope) { DispatchQueue.main.async { cancelledCompletion = true } }
        precondition(model.entered.wait(timeout: .now() + 3) == .success)
        token.cancel(); session.release(scope: scope); model.resume.signal()
        let drain = Message(id: 21, text: "等待旧模型任务正常结束的新消息")
        var drained = false
        session.prepare([drain], accountPeerId: account, scope: .historyView(UUID())) { DispatchQueue.main.async { drained = true } }
        spin { drained }
        precondition(!cancelledCompletion && !session.isPrepared(cancelled, accountPeerId: account), "released scope was repopulated")

        let reviewed = Message(id: 30, text: "阻塞:广告，这条内容实际是需要保留的指南")
        var oldReviewDone = false
        session.prepare([reviewed], accountPeerId: account, scope: scope) { DispatchQueue.main.async { oldReviewDone = true } }
        precondition(model.entered.wait(timeout: .now() + 3) == .success)
        var saved = false
        session.perform(changes: true, { store in try store.save(rgAdSampleDraft(reviewed, store: store)) }) { result in try! result.get(); saved = true }
        spin { saved }
        precondition(!model.hasReleased, "review was blocked by inference")
        var reviewedDone = false
        session.prepare([reviewed], accountPeerId: account, scope: scope) { DispatchQueue.main.async { reviewedDone = true } }
        spin { reviewedDone }
        precondition(session.isPrepared(reviewed, accountPeerId: account, scope: scope) && !session.shouldHide(reviewed, accountPeerId: account, scope: scope))
        model.resume.signal(); spin { oldReviewDone }
        precondition(!session.shouldHide(reviewed, accountPeerId: account, scope: scope), "stale model overrode correction")
        var records: [RGAdSample]?
        session.perform({ try $0.load() }) { records = try! $0.get() }
        spin { records != nil }
        precondition(records!.count == 1 && records![0].reviewedAt != nil && records![0].detection == nil, "cancelled/stale verdict entered training records")

        let covered = Message(id: 31, text: "已经显示过滤结果的商业服务\n#ad")
        let leavingScope = RGAdFilterSession.Scope.historyView(UUID())
        var left = false
        session.prepareProgressively([covered], accountPeerId: account, scope: leavingScope, progress: { _ in
            session.release(scope: leavingScope)
            DispatchQueue.main.async { left = true }
        }, completion: {})
        spin { left }
        records = nil
        session.perform({ try $0.load() }) { records = try! $0.get() }
        spin { records != nil }
        precondition(records!.contains { $0.input.text == covered.text && $0.detection != nil }, "navigation dropped an already displayed detection")
        print("In-flight checks passed: server edits, cancellation, scope release, corrections and recording.")
    }

    static func checkPartialAndReuse(_ root: URL) throws {
        let context = AccountContext(root.path), session = RGAdFilterSession.get(context), account = context.account.peerId
        let model = RGAdSemanticClassifier.shared, scope = RGAdFilterSession.Scope.historyView(UUID())
        let mixed = Message(id: 40, text: "正常介绍 阻塞:混合\n\n#推广 套餐介绍\n\n正常结尾", media: [TelegramMediaImage()])
        var complete = false
        session.prepare([mixed], accountPeerId: account, scope: scope) { DispatchQueue.main.async { complete = true } }
        precondition(model.entered.wait(timeout: .now() + 3) == .success)
        let partial = session.display(mixed, accountPeerId: account, scope: scope)
        precondition(partial.text.contains("正常介绍") && partial.text.contains("正常结尾") && !partial.text.contains("套餐介绍") && partial.media.count == 1)
        precondition(!session.isPrepared(mixed, accountPeerId: account, scope: scope), "partial cut certified an unknown fallback")
        var records: [RGAdSample]?
        session.perform({ try $0.load() }) { records = try! $0.get() }
        spin { records != nil }; precondition(records!.isEmpty, "transient cut was recorded as the final detection")
        let concurrentScope = RGAdFilterSession.Scope.pinnedView(UUID())
        let concurrentCopy = Message(id: mixed.id.id, text: mixed.text, media: mixed.media)
        var preliminaryReady = false, concurrentDone = false
        session.prepareProgressively([concurrentCopy], accountPeerId: account, scope: concurrentScope, progress: { _ in
            DispatchQueue.main.async { preliminaryReady = true }
        }, completion: { DispatchQueue.main.async { concurrentDone = true } })
        spin { preliminaryReady }
        precondition(!session.isPrepared(concurrentCopy, accountPeerId: account, scope: concurrentScope))
        model.resume.signal(); spin { complete }
        precondition(session.isPrepared(mixed, accountPeerId: account, scope: scope))
        precondition(session.isPrepared(concurrentCopy, accountPeerId: account, scope: concurrentScope), "preliminary scoped cut masked a completed shared verdict")
        spin { concurrentDone }
        records = nil
        session.perform({ try $0.load() }) { records = try! $0.get() }
        spin { records != nil }; precondition(records!.count == 1 && records![0].detection != nil)

        // A new message ID with the exact same input reuses its completed semantic result,
        // including mixed content. It must not queue behind this unrelated blocked prediction.
        let blocker = Message(id: 41, text: "阻塞:无关的普通消息")
        var blockerDone = false
        session.prepare([blocker], accountPeerId: account, scope: .historyView(UUID())) { DispatchQueue.main.async { blockerDone = true } }
        precondition(model.entered.wait(timeout: .now() + 3) == .success)
        let before = model.count, duplicate = Message(id: 42, text: mixed.text, media: mixed.media)
        var reused = false
        let reuseScope = RGAdFilterSession.Scope.chatList(UUID())
        let start = ProcessInfo.processInfo.systemUptime
        session.prepare([duplicate], accountPeerId: account, scope: reuseScope) { DispatchQueue.main.async { reused = true } }
        spin { reused }
        precondition(!model.hasReleased && model.count == before)
        precondition(session.isPrepared(duplicate, accountPeerId: account, scope: reuseScope))
        precondition(session.display(duplicate, accountPeerId: account, scope: reuseScope).text == partial.text)
        print("Busy-model exact semantic reuse: \(Int((ProcessInfo.processInfo.systemUptime - start) * 1000)) ms; no additional inference")
        model.resume.signal(); spin { blockerDone }
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-ad-latency-') as directory:
    path = Path(directory)
    (path / 'Checks.swift').write_text(bridge['adapters'] + '\n' + bridge['bridge'] + '\n' + checks)
    (path / 'SemanticAdapter.swift').write_text(contract + adapter)
    sources = [p for p in sorted((root / 'Reza/RGAdFilter/Sources').glob('*.swift')) if p.name != 'AdSemanticClassifier.swift']
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', *map(str, sources), str(path / 'SemanticAdapter.swift'), str(path / 'Checks.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks')], check=True, timeout=30)

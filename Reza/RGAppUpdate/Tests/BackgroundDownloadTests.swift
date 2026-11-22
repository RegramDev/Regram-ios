import Foundation
import CryptoKit

@main struct BackgroundDownloadTests {
    static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        fatalError("Timed out waiting for deterministic I/O")
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data(repeating: 0x52, count: 8192)
        let release = RGUpdateRelease(version: "13.0", build: 34613, downloadURL: URL(string: "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34613/Regram-13.0-b34613.ipa")!, sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), size: Int64(payload.count), notes: "fixture")
        for invalid in ["none", "size", "sha", "host", "status"] {
            let dir = root.appendingPathComponent(invalid)
            let manager = RGUpdateBackgroundDownload(directory: dir)
            let operation = Task { try await manager.download(release: release) { _, _ in } }
            try await wait { URLSession.current?.tasks.last?.resumed == true }
            let session = URLSession.current!, task = session.tasks.last as! URLSessionDownloadTask
            let responseURL = URL(string: invalid == "host" ? "https://evil.example/file" : "https://release-assets.githubusercontent.com/file")!
            task.response = HTTPURLResponse(url: responseURL, statusCode: invalid == "status" ? 503 : 200, httpVersion: nil, headerFields: nil)
            manager.urlSession(session, downloadTask: task, didWriteData: 4096, totalBytesWritten: 4096, totalBytesExpectedToWrite: release.size)
            let temporary = root.appendingPathComponent(UUID().uuidString)
            try (invalid == "sha" ? Data(repeating: 0, count: payload.count) : invalid == "size" ? Data([1]) : payload).write(to: temporary)
            manager.urlSession(session, downloadTask: task, didFinishDownloadingTo: temporary)
            manager.urlSession(session, task: task, didCompleteWithError: nil)
            do {
                let file = try await operation.value
                assert(invalid == "none")
                let saved = try Data(contentsOf: file)
                assert(saved == payload)
                // A separate manager restores the on-disk completed job without another task.
                let restored = RGUpdateBackgroundDownload(directory: dir)
                assert(restored.pendingRelease?.hasSameArtifact(as: release) == true)
                let reused = try await restored.download(release: release) { _, _ in }
                assert(reused == file)
                restored.consume()
                assert(!FileManager.default.fileExists(atPath: dir.path))
            } catch {
                assert(invalid != "none", "Valid background payload rejected: \(error)")
                assert(manager.pendingRelease == nil)
            }
            URLSession.current = nil
        }
        let dir = root.appendingPathComponent("cancel")
        let manager = RGUpdateBackgroundDownload(directory: dir)
        let operation = Task { try await manager.download(release: release) { _, _ in } }
        try await wait { URLSession.current?.tasks.last?.resumed == true }
        let session = URLSession.current!, stale = session.tasks.last as! URLSessionDownloadTask
        operation.cancel()
        do { _ = try await operation.value; fatalError("Cancellation accepted") } catch is CancellationError {}
        assert(stale.cancelled && manager.pendingRelease == nil)
        assert(!FileManager.default.fileExists(atPath: dir.path))
        // Late delegate failures from the cancelled token cannot destroy a fresh job.
        let retry = Task { try await manager.download(release: release) { _, _ in } }
        try await wait { session.tasks.count == 2 }
        manager.urlSession(session, task: stale, didCompleteWithError: NSError(domain: "stale", code: 1))
        assert(manager.pendingRelease != nil)
        retry.cancel()
        do { _ = try await retry.value; fatalError("Retry cancellation accepted") } catch is CancellationError {}
        // Completed metadata with a removed package must restart rather than return a missing path.
        let missing = root.appendingPathComponent("missing")
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        struct Stored: Codable { let release: RGUpdateRelease; let token: UUID; let received: Int64; let complete: Bool }
        try JSONEncoder().encode(Stored(release: release, token: UUID(), received: release.size, complete: true)).write(to: missing.appendingPathComponent("job.json"))
        URLSession.current = nil
        let restored = RGUpdateBackgroundDownload(directory: missing)
        let restart = Task { try await restored.download(release: release) { _, _ in } }
        try await wait { URLSession.current?.tasks.last?.resumed == true }
        restart.cancel()
        do { _ = try await restart.value; fatalError("Restart cancellation accepted") } catch is CancellationError {}
        // Reattach a system-owned task after a process restart, rejecting duplicates and other tokens.
        let reattach = root.appendingPathComponent("reattach"), token = UUID()
        try FileManager.default.createDirectory(at: reattach, withIntermediateDirectories: true)
        try JSONEncoder().encode(Stored(release: release, token: token, received: 4096, complete: false)).write(to: reattach.appendingPathComponent("job.json"))
        let good = URLSessionDownloadTask(url: release.downloadURL, identifier: 41)
        good.taskDescription = token.uuidString
        let duplicate = URLSessionDownloadTask(url: release.downloadURL, identifier: 42)
        duplicate.taskDescription = token.uuidString
        let wrong = URLSessionDownloadTask(url: release.downloadURL, identifier: 43)
        wrong.taskDescription = UUID().uuidString
        URLSession.recoveredTasks = [good, duplicate, wrong]
        let reattached = RGUpdateBackgroundDownload(directory: reattach)
        let reattachedOperation = Task { try await reattached.download(release: release) { _, _ in } }
        try await wait { good.resumed }
        assert(duplicate.cancelled && wrong.cancelled && URLSession.current.tasks.count == 3)
        // Cancelling while the system enumerates tasks must not start a new download.
        reattachedOperation.cancel()
        do { _ = try await reattachedOperation.value; fatalError("Reattached cancellation accepted") } catch is CancellationError {}
        URLSession.current.holdEnumeration = true
        let delayed = Task { try await reattached.download(release: release) { _, _ in } }
        try await wait { URLSession.current.enumeration != nil }
        delayed.cancel()
        do { _ = try await delayed.value; fatalError("Enumeration cancellation accepted") } catch is CancellationError {}
        URLSession.current.enumeration?([])
        assert(reattached.pendingRelease == nil && URLSession.current.tasks.count == 3)
        assert(!RGUpdateBackgroundDownload.allowedDownloadHost("githubusercontent.com.evil.example"))
        print("Background transfer: verified bytes/hash/HTTPS host/status, completed-job restart reuse, cleanup, missing-file recovery, cancellation and stale-token isolation passed.")
    }
}

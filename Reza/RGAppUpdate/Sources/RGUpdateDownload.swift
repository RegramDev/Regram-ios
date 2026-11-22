// MARK: Regram — use a delegate-based download task so progress is delivered.
import Foundation

final class RGUpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int64
    private let onProgress: @Sendable (Double, Int64) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var downloaded: Result<Void, Error>?
    private var cancelled = false

    init(destination: URL, expectedSize: Int64, onProgress: @escaping @Sendable (Double, Int64) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    func download(from url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                guard !cancelled else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: url)
                self.session = session
                self.task = task
                self.continuation = continuation
                lock.unlock()
                task.resume()
            }
        }, onCancel: { self.cancel() })
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, RGUpdateRelease.validHTTPS(url) else { completionHandler(nil); return }
        let host = url.host?.lowercased() ?? ""
        completionHandler(host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com") ? request : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= expectedSize, totalBytesExpectedToWrite <= expectedSize else {
            finish(.failure(RGUpdateError.hashMismatch))
            return
        }
        lock.lock()
        let active = continuation != nil && !cancelled
        lock.unlock()
        if active { onProgress(min(1, Double(totalBytesWritten) / Double(max(1, expectedSize))), totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard continuation != nil, !cancelled else { return }
        // URLSession removes its temporary file after this delegate returns.
        // Move it now, before resuming the waiting async operation.
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw RGUpdateError.network }
            let size = try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber
            guard size?.int64Value == expectedSize else { throw RGUpdateError.hashMismatch }
            try FileManager.default.moveItem(at: location, to: destination)
            downloaded = .success(())
        } catch { downloaded = .failure(error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let result = downloaded
        lock.unlock()
        if let error { finish(.failure(error)) }
        else { finish(result ?? .failure(RGUpdateError.network)) }
    }
}

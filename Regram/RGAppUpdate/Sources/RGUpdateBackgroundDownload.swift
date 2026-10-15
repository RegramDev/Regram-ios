// MARK: Regram — one persistent system-owned IPA transfer, recoverable after suspension or process termination.
import Foundation

final class RGUpdateBackgroundDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = RGUpdateBackgroundDownload()
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "Regram") + ".Regram.Update.Download" }
    private struct Job: Codable {
        let release: RGUpdateRelease
        var token = UUID()
        var received: Int64 = 0
        var complete = false
    }
    private let lock = NSRecursiveLock()
    private let directory: URL
    private var metadata: URL { directory.appendingPathComponent("job.json") }
    private var package: URL { directory.appendingPathComponent("incoming.ipa") }
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var job: Job?
    private var waiter: CheckedContinuation<URL, Error>?
    private var progress: (@Sendable (Double, Int64) -> Void)?
    private var backgroundCompletion: (() -> Void)?
    private var restoring = false
    private var generation = UUID()
    var pendingRelease: RGUpdateRelease? { lock.lock(); defer { lock.unlock() }; return job?.release }

    private override convenience init() {
        self.init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RegramUpdateTransfer", isDirectory: true))
    }

    init(directory: URL) {
        self.directory = directory
        super.init()
        if let data = try? Data(contentsOf: metadata), let stored = try? JSONDecoder().decode(Job.self, from: data), (try? stored.release.validateCachedMetadata()) != nil {
            job = stored
        }
    }

    private func getSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true; configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true; configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 3600
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session; return session
    }

    func download(release: RGUpdateRelease, onProgress: @escaping @Sendable (Double, Int64) -> Void) async throws -> URL {
        try release.validateCachedMetadata()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock(); defer { lock.unlock() }
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                guard waiter == nil else { continuation.resume(throwing: RGUpdateError.network); return }
                do {
                    if let job, !job.release.hasSameArtifact(as: release) { cancelLocked() }
                    if job?.complete == true, FileManager.default.fileExists(atPath: package.path) {
                        continuation.resume(returning: package); return
                    }
                    if job?.complete == true { job?.complete = false; job?.received = 0 }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                    var values = URLResourceValues(); values.isExcludedFromBackup = true
                    var excludedDirectory = directory; try excludedDirectory.setResourceValues(values)
                    if job == nil { job = Job(release: release); try persist() }
                    waiter = continuation; progress = onProgress
                    if task != nil || restoring { return }
                    restoring = true
                    let token = generation
                    getSession().getAllTasks { [weak self] tasks in
                        guard let self else { return }
                        self.lock.lock(); defer { self.lock.unlock() }
                        guard token == self.generation, self.job?.release.hasSameArtifact(as: release) == true else { return }
                        self.restoring = false
                        if self.job?.complete == true { self.complete(.success(self.package)); return }
                        let matches = tasks.compactMap { $0 as? URLSessionDownloadTask }.filter { $0.originalRequest?.url == release.downloadURL && $0.taskDescription == self.job?.token.uuidString }
                        for task in tasks where !matches.contains(where: { $0.taskIdentifier == task.taskIdentifier }) { task.cancel() }
                        if let existing = matches.first { self.task = existing; for duplicate in matches.dropFirst() { duplicate.cancel() } }
                        else {
                            self.job?.received = 0
                            self.task = self.getSession().downloadTask(with: release.downloadURL)
                            self.task?.taskDescription = self.job?.token.uuidString
                        }
                        let bytes = max(self.job?.received ?? 0, self.task?.countOfBytesReceived ?? 0)
                        self.progress?(min(1, Double(bytes) / Double(max(1, release.size))), bytes)
                        self.task?.resume()
                    }
                } catch { job = nil; waiter = nil; progress = nil; continuation.resume(throwing: error) }
            }
        }, onCancel: { self.cancel() })
    }

    func attachBackgroundEvents(identifier: String, completion: @escaping () -> Void) -> Bool {
        guard identifier == Self.identifier else { return false }
        lock.lock(); defer { lock.unlock() }
        if let previous = backgroundCompletion { DispatchQueue.main.async(execute: previous) }
        backgroundCompletion = completion
        _ = getSession()
        return true
    }

    func consume() {
        lock.lock(); defer { lock.unlock() }
        guard job?.complete == true else { return }
        job = nil; task = nil; generation = UUID()
        try? FileManager.default.removeItem(at: directory)
    }

    func cancel() { lock.lock(); defer { lock.unlock() }; cancelLocked() }
    private func cancelLocked() {
        let oldToken = job?.token.uuidString
        if let oldToken {
            getSession().getAllTasks { tasks in
                for task in tasks where task.taskDescription == oldToken { task.cancel() }
            }
        }
        generation = UUID(); restoring = false
        task?.cancel(); task = nil; job = nil
        let continuation = waiter; waiter = nil; progress = nil
        try? FileManager.default.removeItem(at: directory)
        continuation?.resume(throwing: CancellationError())
    }

    private func persist() throws {
        guard let job else { return }
        try JSONEncoder().encode(job).write(to: metadata, options: .atomic)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: metadata.path)
    }

    private func complete(_ result: Result<URL, Error>) {
        let continuation = waiter; waiter = nil; progress = nil; task = nil
        if case .failure = result { job = nil; try? FileManager.default.removeItem(at: directory) }
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock(); defer { lock.unlock() }
        guard let job, isCurrent(downloadTask) else { return }
        guard totalBytesWritten <= job.release.size, totalBytesExpectedToWrite <= job.release.size else {
            downloadTask.cancel(); complete(.failure(RGUpdateError.hashMismatch)); return
        }
        if totalBytesWritten - job.received >= 1024 * 1024 { self.job?.received = totalBytesWritten; try? persist() }
        progress?(min(1, Double(totalBytesWritten) / Double(max(1, job.release.size))), totalBytesWritten)
    }

    private func isCurrent(_ task: URLSessionTask) -> Bool {
        guard let job, task.taskDescription == job.token.uuidString, task.originalRequest?.url == job.release.downloadURL else { return false }
        return self.task == nil || self.task?.taskIdentifier == task.taskIdentifier
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock(); defer { lock.unlock() }
        guard var job, isCurrent(downloadTask) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  let url = response.url, RGUpdateRelease.validHTTPS(url), Self.allowedDownloadHost(url.host ?? "") else { throw RGUpdateError.network }
            let size = try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber
            guard size?.int64Value == job.release.size, try RGUpdateCache.hashFile(location) == job.release.sha256 else { throw RGUpdateError.hashMismatch }
            try? FileManager.default.removeItem(at: package)
            try FileManager.default.moveItem(at: location, to: package)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: package.path)
            job.complete = true; self.job = job; try persist()
            progress?(1, job.release.size)
        } catch { complete(.failure(error)) }
    }

    static func allowedDownloadHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); defer { lock.unlock() }
        guard isCurrent(task) else { return }
        if let error { complete(.failure(error)) }
        else if job?.complete == true { complete(.success(package)) }
        else { complete(.failure(RGUpdateError.network)) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock(); let completion = backgroundCompletion; backgroundCompletion = nil; lock.unlock()
        if let completion { DispatchQueue.main.async(execute: completion) }
    }
}

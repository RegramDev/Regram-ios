import Foundation

private final class ProgressSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Double, Int64)] = []
    func record(_ progress: Double, _ bytes: Int64) {
        lock.lock(); defer { lock.unlock() }
        values.append((progress, bytes))
    }
    func snapshot() -> [(Double, Int64)] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

@main struct DownloadProgressTests {
    static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let expectedSize: Int64 = 3 * 1024 * 1024
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 15
        for endpoint in ["file", "unknown-size"] {
            let samples = ProgressSamples()
            let destination = directory.appendingPathComponent(endpoint)
            let download = RGUpdateDownload(destination: destination, expectedSize: expectedSize) { samples.record($0, $1) }
            try await download.download(from: base.appendingPathComponent(endpoint), configuration: configuration)
            let values = samples.snapshot()
            assert(values.contains { $0.0 > 0 && $0.0 < 1 }, "No intermediate progress callback")
            assert(values.last?.1 == expectedSize, "Download did not report its final byte count")
            assert(values.allSatisfy { $0.0 >= 0 && $0.0 <= 1 })
            for pair in zip(values, values.dropFirst()) { assert(pair.0.1 <= pair.1.1) }
            let bytes = try Data(contentsOf: destination)
            assert(bytes.count == expectedSize && bytes.allSatisfy { $0 == 0x52 }, "Delegate temporary file was lost or corrupted")
        }
        for (endpoint, size, expectedKey) in [
            ("file", Int64(1024), "AppUpdate.HashMismatch"),
            ("file", expectedSize + 1, "AppUpdate.HashMismatch"),
            ("error", Int64(16), "AppUpdate.NetworkError"),
            ("redirect", expectedSize, "AppUpdate.NetworkError")
        ] {
            let destination = directory.appendingPathComponent(UUID().uuidString)
            let download = RGUpdateDownload(destination: destination, expectedSize: size) { _, _ in }
            do {
                try await download.download(from: base.appendingPathComponent(endpoint), configuration: configuration)
                fatalError("Invalid download accepted")
            } catch let error as RGUpdateError { assert(error.localizationKey == expectedKey) }
            assert(!FileManager.default.fileExists(atPath: destination.path))
        }
        for cancelBeforeStart in [false, true] {
            let destination = directory.appendingPathComponent(UUID().uuidString)
            let download = RGUpdateDownload(destination: destination, expectedSize: expectedSize) { _, _ in }
            let operation = Task { try await download.download(from: base.appendingPathComponent("file"), configuration: configuration) }
            if !cancelBeforeStart { try await Task.sleep(nanoseconds: 100_000_000) }
            operation.cancel()
            do { try await operation.value; fatalError("Cancelled download succeeded") }
            catch is CancellationError {}
            assert(!FileManager.default.fileExists(atPath: destination.path))
        }
        print("Download checks passed: intermediate progress with/without Content-Length, complete bytes, size limits, HTTP errors, rejected redirects and cancellation.")
    }
}

import Foundation

private final class PackageRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func record() { lock.lock(); value += 1; lock.unlock() }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}

@main struct LocalUpdateServerTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fixture.ipa")
        let bytes = Data((0..<900000).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let server = try RGLocalUpdateServer(fileURL: file)
        let requests = PackageRequests()
        let deliveries = PackageRequests()
        server.packageRequested = { requests.record() }
        server.packageDelivered = { deliveries.record() }
        let url = try await server.start()
        defer { server.stop() }
        assert(url.host == "127.0.0.1")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var probe = URLRequest(url: url)
        probe.httpMethod = "HEAD"
        _ = try await session.data(for: probe)
        assert(requests.count() == 0, "HEAD must not be treated as installation starting")
        assert(deliveries.count() == 0)
        let (complete, response) = try await session.data(from: url)
        assert((response as? HTTPURLResponse)?.statusCode == 200 && complete == bytes)
        assert(requests.count() == 1)
        // The complete file, rather than just a GET probe, confirms delivery to TrollStore.
        for _ in 0..<20 {
            if deliveries.count() == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        assert(deliveries.count() == 1)
        var request = URLRequest(url: url)
        request.setValue("bytes=17-100016", forHTTPHeaderField: "Range")
        let (part, partResponse) = try await session.data(for: request)
        assert((partResponse as? HTTPURLResponse)?.statusCode == 206 && part == bytes.subdata(in: 17..<100017))
        request.setValue("bytes=899990-", forHTTPHeaderField: "Range")
        let (tail, _) = try await session.data(for: request)
        assert(tail == bytes.suffix(10))
        assert(deliveries.count() == 1, "Partial requests must not report complete delivery")
        request.setValue("bytes=9999999-", forHTTPHeaderField: "Range")
        let (_, invalidResponse) = try await session.data(for: request)
        assert((invalidResponse as? HTTPURLResponse)?.statusCode == 416)
        request.setValue(nil, forHTTPHeaderField: "Range")
        request.httpMethod = "HEAD"
        let (head, headResponse) = try await session.data(for: request)
        assert(head.isEmpty && (headResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length") == String(bytes.count))
        let invalidURL = URL(string: "http://127.0.0.1:\(url.port!)/wrong/Regram.ipa")!
        let (_, missingResponse) = try await session.data(from: invalidURL)
        assert((missingResponse as? HTTPURLResponse)?.statusCode == 404)
        async let a = session.data(from: url)
        async let b = session.data(from: url)
        let concurrent = try await (a, b)
        assert(concurrent.0.0 == bytes && concurrent.1.0 == bytes)
        assert(requests.count() == 1, "Repeated Range/GET requests must not produce duplicate installation-start events")
        print("Local delivery checks passed: actual package request detection, HEAD exclusion, loopback binding, exact bytes, concurrent requests, ranges and invalid routes.")
    }
}

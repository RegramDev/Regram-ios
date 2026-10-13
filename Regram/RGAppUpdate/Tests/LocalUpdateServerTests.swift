import Foundation

@main struct LocalUpdateServerTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fixture.ipa")
        let bytes = Data((0..<900000).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let server = try RGLocalUpdateServer(fileURL: file)
        let url = try await server.start()
        defer { server.stop() }
        assert(url.host == "127.0.0.1")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (complete, response) = try await session.data(from: url)
        assert((response as? HTTPURLResponse)?.statusCode == 200 && complete == bytes)
        var request = URLRequest(url: url)
        request.setValue("bytes=17-100016", forHTTPHeaderField: "Range")
        let (part, partResponse) = try await session.data(for: request)
        assert((partResponse as? HTTPURLResponse)?.statusCode == 206 && part == bytes.subdata(in: 17..<100017))
        request.setValue("bytes=899990-", forHTTPHeaderField: "Range")
        let (tail, _) = try await session.data(for: request)
        assert(tail == bytes.suffix(10))
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
        print("Local delivery checks passed: loopback binding, exact bytes, HEAD, concurrent requests, ranges and invalid routes.")
    }
}

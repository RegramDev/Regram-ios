// MARK: Regram — local IPA delivery for Apple's installer, using a remote HTTPS manifest.
import Foundation
import Network

final class RGLocalUpdateServer: @unchecked Sendable {
    private let fileURL: URL
    private let size: UInt64
    private let route = "/" + UUID().uuidString + "/Regram.ipa"
    private let queue = DispatchQueue(label: "Regram.Update.Loopback")
    private let listener: NWListener
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var ready: ((Result<URL, Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var stopped = false
    private var reportedPackageRequest = false
    var closed: (@Sendable () -> Void)?
    var packageRequested: (@Sendable () -> Void)?
    var packageDelivered: (@Sendable () -> Void)?

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 0 else { throw RGUpdateError.invalidArchive }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.ready = { continuation.resume(with: $0) }
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)" + self.route) else { self.finishStart(.failure(RGUpdateError.network)); return }
                        self.finishStart(.success(url))
                    case .failed:
                        self.finishStart(.failure(RGUpdateError.network)); self.stopOnQueue()
                    default: break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    guard let self, !self.stopped, self.connections.count < 8 else { connection.cancel(); return }
                    self.connections[ObjectIdentifier(connection)] = connection
                    connection.stateUpdateHandler = { [weak self, weak connection] state in
                        guard let self, let connection else { return }
                        switch state {
                        case .ready: self.receive(connection, buffer: Data())
                        case .failed, .cancelled: self.connections.removeValue(forKey: ObjectIdentifier(connection))
                        default: break
                        }
                    }
                    connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 60) { [weak connection] in connection?.cancel() }
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 5) {
                    if self.ready != nil { self.finishStart(.failure(RGUpdateError.network)); self.stopOnQueue() }
                }
                let timeout = DispatchWorkItem { [weak self] in self?.stopOnQueue() }
                self.timeout = timeout
                self.queue.asyncAfter(deadline: .now() + 300, execute: timeout)
            }
        }
    }

    func stop() { queue.async { self.stopOnQueue() } }

    private func finishStart(_ result: Result<URL, Error>) {
        let callback = ready; ready = nil; callback?(result)
    }

    private func stopOnQueue() {
        guard !stopped else { return }
        stopped = true; timeout?.cancel(); timeout = nil
        listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil; listener.cancel()
        for connection in connections.values { connection.stateUpdateHandler = nil; connection.cancel() }
        connections.removeAll()
        finishStart(.failure(RGUpdateError.cancelled))
        closed?(); closed = nil
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 16384, error == nil else { connection.cancel(); return }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(connection, request: buffer) }
            else if complete { connection.cancel() }
            else { self.receive(connection, buffer: buffer) }
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        guard let text = String(data: request, encoding: .utf8) else { connection.cancel(); return }
        let lines = text.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3, parts[1] == route, parts[0] == "GET" || parts[0] == "HEAD" else {
            sendError(connection, status: "404 Not Found"); return
        }
        let method = String(parts[0])
        var lower: UInt64 = 0, upper = size - 1, partial = false
        let ranges = lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") }
        guard ranges.count <= 1 else { sendError(connection, status: "416 Range Not Satisfiable"); return }
        if let range = ranges.first {
            let value = range.dropFirst(6).trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("bytes="), !value.contains(",") else { sendError(connection, status: "416 Range Not Satisfiable"); return }
            let pair = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            guard pair.count == 2, let start = UInt64(pair[0]), start < size else { sendError(connection, status: "416 Range Not Satisfiable"); return }
            lower = start
            if !pair[1].isEmpty {
                guard let end = UInt64(pair[1]), end >= start else { sendError(connection, status: "416 Range Not Satisfiable"); return }
                upper = min(end, size - 1)
            }
            partial = true
        }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            try handle.seek(toOffset: lower)
            if method == "GET", !reportedPackageRequest {
                reportedPackageRequest = true
                packageRequested?()
            }
            var header = "HTTP/1.1 \(partial ? "206 Partial Content" : "200 OK")\r\nContent-Type: application/octet-stream\r\nContent-Length: \(upper - lower + 1)\r\nAccept-Ranges: bytes\r\nConnection: close\r\nCache-Control: no-store\r\n"
            if partial { header += "Content-Range: bytes \(lower)-\(upper)/\(size)\r\n" }
            header += "\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection, error == nil, method != "HEAD" else { try? handle.close(); connection?.cancel(); return }
                self.sendFile(connection, handle: handle, remaining: upper - lower + 1, reportDelivery: lower == 0 && upper == self.size - 1)
            })
        } catch { sendError(connection, status: "500 Internal Server Error") }
    }

    private func sendFile(_ connection: NWConnection, handle: FileHandle, remaining: UInt64, reportDelivery: Bool) {
        do {
            guard !stopped, remaining > 0, let chunk = try handle.read(upToCount: Int(min(256 * 1024, remaining))), !chunk.isEmpty else { try? handle.close(); connection.cancel(); return }
            connection.send(content: chunk, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection, error == nil else { try? handle.close(); connection?.cancel(); return }
                let rest = remaining - UInt64(chunk.count)
                if rest == 0 {
                    try? handle.close(); connection.cancel()
                    if reportDelivery { self.packageDelivered?() }
                }
                else { self.sendFile(connection, handle: handle, remaining: rest, reportDelivery: reportDelivery) }
            })
        } catch { try? handle.close(); connection.cancel() }
    }

    private func sendError(_ connection: NWConnection, status: String) {
        connection.send(content: Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

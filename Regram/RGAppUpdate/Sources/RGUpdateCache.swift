// MARK: Regram — verified downloads and signed updates survive process restarts.
import Foundation
import CryptoKit

final class RGUpdateCache: @unchecked Sendable {
    struct State: Sendable {
        let release: RGUpdateRelease
        let downloaded: URL?
        let prepared: URL?
    }

    private struct Signed: Codable {
        let hash: String
        let size: Int64
        let signer: String
    }

    private struct Record: Codable {
        var schema = 1
        var release: RGUpdateRelease
        var downloaded = false
        var signed: Signed?
    }

    let directory: URL
    private let lock = NSRecursiveLock()
    private var metadata: URL { directory.appendingPathComponent("update.json") }
    private var raw: URL { directory.appendingPathComponent("release.ipa") }
    private var signed: URL { directory.appendingPathComponent("signed.ipa") }

    init(directory: URL) { self.directory = directory }

    // Only hashes enter cache metadata; certificate bytes and passwords stay in Keychain.
    static func signerFingerprint(certificate: Data, profiles: [Data], bundleId: String, installedBuild: String) -> String {
        let components = [bundleId, installedBuild, hash(certificate)] + profiles.map { hash($0) }.sorted()
        return hash(Data(components.joined(separator: "\n").utf8))
    }

    static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var result = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { result.update(data: data) }
        return result.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func load(installedVersion: String, installedBuild: String, signer: String?) throws -> State? {
        lock.lock(); defer { lock.unlock() }
        guard var record = try read() else { return nil }
        guard record.release.isNewer(version: installedVersion, build: installedBuild) else { try clear(); return nil }
        var changed = false
        var downloaded: URL?
        if record.downloaded {
            if try valid(raw, size: record.release.size, hash: record.release.sha256) { downloaded = raw }
            else { try remove(raw); record.downloaded = false; changed = true }
        }
        var prepared: URL?
        if let descriptor = record.signed, let signer {
            if descriptor.signer == signer, try valid(signed, size: descriptor.size, hash: descriptor.hash) { prepared = signed }
            else { try remove(signed); record.signed = nil; changed = true }
        }
        if changed { try write(record) }
        return State(release: record.release, downloaded: downloaded, prepared: prepared)
    }

    func select(_ release: RGUpdateRelease) throws {
        lock.lock(); defer { lock.unlock() }
        try release.validateCachedMetadata()
        if var record = try read(), record.release.hasSameArtifact(as: release) {
            record.release = release
            try write(record)
        } else {
            try clear()
            try write(Record(release: release))
        }
    }

    func saveDownloaded(_ file: URL, release: RGUpdateRelease) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard try valid(file, size: release.size, hash: release.sha256) else { throw RGUpdateError.hashMismatch }
        try select(release)
        guard var record = try read() else { throw RGUpdateError.cache }
        try replace(file, at: raw)
        record.downloaded = true
        try write(record)
        return raw
    }

    func saveSigned(_ file: URL, release: RGUpdateRelease, signer: String) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard var record = try read(), record.release.hasSameArtifact(as: release) else { throw RGUpdateError.cache }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard let size, size.int64Value > 0 else { throw RGUpdateError.invalidArchive }
        let descriptor = Signed(hash: try Self.hashFile(file), size: size.int64Value, signer: signer)
        try replace(file, at: signed)
        record.signed = descriptor
        try write(record)
        return signed
    }

    func discardSigned() throws {
        lock.lock(); defer { lock.unlock() }
        guard var record = try read() else { return }
        try remove(signed)
        record.signed = nil
        try write(record)
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func read() throws -> Record? {
        guard FileManager.default.fileExists(atPath: metadata.path) else { return nil }
        // Read errors, including protected data before unlock, must not destroy a good cache.
        let data = try Data(contentsOf: metadata)
        guard data.count <= 256 * 1024, let record = try? JSONDecoder().decode(Record.self, from: data), record.schema == 1,
              (try? record.release.validateCachedMetadata()) != nil else { try clear(); return nil }
        return record
    }

    private func write(_ record: Record) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try JSONEncoder().encode(record).write(to: metadata, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: metadata.path)
        #endif
    }

    private func valid(_ file: URL, size: Int64, hash: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let actualSize = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard actualSize?.int64Value == size else { return false }
        return try Self.hashFile(file) == hash
    }

    private func remove(_ file: URL) throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func replace(_ source: URL, at destination: URL) throws {
        try remove(destination)
        try FileManager.default.moveItem(at: source, to: destination)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
    }
}

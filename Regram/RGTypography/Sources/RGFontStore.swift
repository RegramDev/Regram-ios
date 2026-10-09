import Foundation
import Combine
import CoreText
import CryptoKit
import AppBundle
import ZipArchive
import RGSimpleSettings

private struct RGCloudFont: Decodable {
    let file: String
    let source: URL
    let sha256: String
    let bytes: Int
    let archive_member: String?
    let archive_sha256: String?
}
public struct RGDownloadableFontFamily: Decodable, Identifiable {
    public let id: String
    public let title: String
    public let group: String
    public let regular: String
    public let italic: String?
    public let selectionId: String
}
private struct RGCloudCatalog: Decodable {
    let files: [RGCloudFont]
    let families: [RGDownloadableFontFamily]?
}

public struct RGImportedFont: Codable, Identifiable {
    public let id: String
    public let title: String
    public let latin: Bool
    public let chinese: Bool
}

public enum RGFontStoreError: Error {
    case unavailable, invalidFont, tooLarge, integrity
}

/// All font downloads are explicit. Complete families are published atomically; partial downloads
/// are never registered. Imported files are copied out of the document provider's security scope.
@MainActor public final class RGFontStore: ObservableObject {
    public static let shared = RGFontStore()
    @Published public private(set) var imported: [RGImportedFont] = []
    @Published public private(set) var downloading: String?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var revision = 0
    private var operation: Task<Void, Never>?
    private var progressObservation: NSKeyValueObservation?
    private var activeTask: URLSessionDownloadTask?
    private var operationId = UUID()

    nonisolated private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("RegramFonts", isDirectory: true)
    }
    nonisolated private static let catalog: [RGCloudFont] = {
        guard let url = getAppBundle().url(forResource: "RGFontCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(RGCloudCatalog.self, from: data) else { return [] }
        return value.files
    }()
    nonisolated public static let additionalFamilies: [RGDownloadableFontFamily] = {
        guard let url = getAppBundle().url(forResource: "RGFontCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(RGCloudCatalog.self, from: data) else { return [] }
        return value.families ?? []
    }()
    nonisolated private static func entries(prefix: String) -> [RGCloudFont] {
        return self.catalog.filter { $0.file.hasPrefix(prefix + "-") }
    }
    nonisolated public static func cachedURL(filename: String) -> URL? {
        guard let entry = self.catalog.first(where: { $0.file == filename }) else { return nil }
        let prefix = String(filename.prefix { $0 != "-" })
        let url = self.root.appendingPathComponent("Cloud/\(prefix)/\(entry.file)")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == entry.bytes else { return nil }
        return url
    }
    nonisolated public static func importedURL(id: String, italic: Bool = false) -> URL? {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { return nil }
        if let family = self.additionalFamilies.first(where: { $0.selectionId == id }),
           let url = self.cachedURL(filename: italic ? (family.italic ?? family.regular) : family.regular) { return url }
        let url = self.root.appendingPathComponent("Imported/\(id).font")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    public func isDownloaded(prefix: String?) -> Bool {
        guard let prefix else { return true }
        let entries = Self.entries(prefix: prefix)
        return !entries.isEmpty && entries.allSatisfy { Self.cachedURL(filename: $0.file) != nil }
    }
    private init() {
        if let data = try? Data(contentsOf: Self.root.appendingPathComponent("imported.json")),
           let values = try? JSONDecoder().decode([RGImportedFont].self, from: data) {
            self.imported = values.filter { Self.importedURL(id: $0.id) != nil }
        }
    }
    public func cancel() {
        self.operationId = UUID()
        self.operation?.cancel()
        self.activeTask?.cancel()
        self.activeTask = nil
        self.progressObservation = nil
        self.downloading = nil
    }
    private func publishRevision() {
        self.revision += 1
        RGSimpleSettings.shared.fontAssetsRevision += 1
    }
    private func fetch(url: URL, base: Double, portion: Double) async throws -> URL {
        let id = self.operationId
        return try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: url) { temporary, response, error in
                    do {
                        if let error { throw error }
                        guard let response = response as? HTTPURLResponse, response.statusCode == 200, let temporary else { throw RGFontStoreError.unavailable }
                        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        continuation.resume(returning: destination)
                    } catch { continuation.resume(throwing: error) }
                }
                self.activeTask = task
                self.progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] value, _ in
                    let progress = value.fractionCompleted
                    Task { @MainActor [weak self] in
                        guard let self, self.operationId == id else { return }
                        self.progress = base + portion * progress
                    }
                }
                task.resume()
        }
    }
    public func download(prefix: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard self.downloading == nil else { return }
        let files = Self.entries(prefix: prefix)
        guard !files.isEmpty else { completion(.failure(RGFontStoreError.unavailable)); return }
        let id = UUID()
        self.operationId = id
        self.downloading = prefix
        self.progress = 0
        self.operation = Task { [weak self] in
            guard let self else { return }
            let stage = FileManager.default.temporaryDirectory.appendingPathComponent("RegramFonts-\(id.uuidString)")
            var archives: [URL: URL] = [:]
            defer {
                try? FileManager.default.removeItem(at: stage)
                for url in archives.values { try? FileManager.default.removeItem(at: url) }
                if self.operationId == id {
                    self.downloading = nil
                    self.activeTask = nil
                    self.progressObservation = nil
                    self.operation = nil
                }
            }
            do {
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                for (index, file) in files.enumerated() {
                    try Task.checkCancellation()
                    let base = Double(index) / Double(files.count)
                    let portion = 1.0 / Double(files.count)
                    let temporary: URL
                    if let cached = archives[file.source] { temporary = cached }
                    else {
                        temporary = try await self.fetch(url: file.source, base: base, portion: portion)
                        archives[file.source] = temporary
                    }
                    try Task.checkCancellation()
                    try await Task.detached {
                        let values = try temporary.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? Int.max) <= 100 * 1024 * 1024 else { throw RGFontStoreError.tooLarge }
                        let destination = stage.appendingPathComponent(file.file)
                        if let member = file.archive_member, let hash = file.archive_sha256 {
                            let archive = try Data(contentsOf: temporary, options: .mappedIfSafe)
                            guard Self.hash(archive) == hash else { throw RGFontStoreError.integrity }
                            guard SSZipArchive.extractFileFromArchive(atPath: temporary.path, filePath: member, toPath: destination.path) else { throw RGFontStoreError.integrity }
                        } else { try FileManager.default.copyItem(at: temporary, to: destination) }
                        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
                        guard data.count == file.bytes, Self.hash(data) == file.sha256,
                              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else { throw RGFontStoreError.integrity }
                    }.value
                    self.progress = Double(index + 1) / Double(files.count)
                }
                try Task.checkCancellation()
                let cloud = Self.root.appendingPathComponent("Cloud", isDirectory: true)
                try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
                var excluded = cloud
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try excluded.setResourceValues(values)
                let destination = cloud.appendingPathComponent(prefix, isDirectory: true)
                if !self.isDownloaded(prefix: prefix) {
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.moveItem(at: stage, to: destination)
                }
                self.publishRevision()
                completion(.success(()))
            } catch {
                if self.operationId == id { completion(.failure(error)) }
            }
        }
    }
    nonisolated private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func importFont(url: URL, completion: @escaping (Result<RGImportedFont, Error>) -> Void) {
        Task {
            do {
                let value = try await Task.detached { () -> RGImportedFont in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? Int.max) <= 64 * 1024 * 1024 else { throw RGFontStoreError.tooLarge }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard !data.isEmpty, data.count <= 64 * 1024 * 1024 else { throw RGFontStoreError.tooLarge }
                    guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else { throw RGFontStoreError.invalidFont }
                    let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
                    guard let charset = CTFontCopyCharacterSet(font) as CharacterSet? else { throw RGFontStoreError.invalidFont }
                    let latin = charset.contains("A".unicodeScalars.first!) && charset.contains("a".unicodeScalars.first!)
                    let chinese = charset.contains("中".unicodeScalars.first!)
                    guard latin || chinese else { throw RGFontStoreError.invalidFont }
                    let id = Self.hash(data)
                    let directory = Self.root.appendingPathComponent("Imported", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let destination = directory.appendingPathComponent("\(id).font")
                    if !FileManager.default.fileExists(atPath: destination.path) { try data.write(to: destination, options: .atomic) }
                    let title = (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? url.deletingPathExtension().lastPathComponent
                    return RGImportedFont(id: id, title: title, latin: latin, chinese: chinese)
                }.value
                if !self.imported.contains(where: { $0.id == value.id }) {
                    let updated = self.imported + [value]
                    try JSONEncoder().encode(updated).write(to: Self.root.appendingPathComponent("imported.json"), options: .atomic)
                    self.imported = updated
                }
                self.publishRevision()
                completion(.success(value))
            } catch { completion(.failure(error)) }
        }
    }
}

// MARK: Regram
import Foundation
import UIKit
import Combine
import CryptoKit
import SwiftSignalKit
import RGUpdateSigner

public let rgAvailableAppUpdate = ValuePromise<RGUpdateRelease?>(nil, ignoreRepeated: true)

private final class RGUpdateNetworkDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, URLSessionDataDelegate, @unchecked Sendable {
    let service: URL?
    let maximumSize: Int64
    var progress: ((Double) -> Void)?
    init(service: URL?, maximumSize: Int64) { self.service = service; self.maximumSize = maximumSize }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, RGUpdateRelease.validHTTPS(url) else { completionHandler(nil); return }
        if let service {
            // Never redirect a signed package or upload credentials to another origin.
            guard RGLCSignNode.trustedURL(url), RGLCSignNode.trustedURL(service) else { completionHandler(nil); return }
        } else {
            let host = url.host?.lowercased() ?? ""
            guard host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com") else { completionHandler(nil); return }
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(response.expectedContentLength > maximumSize ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumSize || totalBytesExpectedToWrite > maximumSize { downloadTask.cancel(); return }
        progress?(min(1.0, Double(totalBytesWritten) / Double(max(1, maximumSize))))
    }
}

@MainActor public final class RGAppUpdater: ObservableObject {
    public static let shared = RGAppUpdater()
    public enum Stage: Equatable {
        case idle, checking, available, upToDate, downloading, signing, uploading, ready, installRequested, failed(String)
        public var isBusy: Bool { [.checking, .downloading, .signing, .uploading].contains(self) }
        public var localizationKey: String {
            switch self {
            case .idle: return "AppUpdate.Check"
            case .checking: return "AppUpdate.Checking"
            case .available: return "AppUpdate.Available"
            case .upToDate: return "AppUpdate.UpToDate"
            case .downloading: return "AppUpdate.Downloading"
            case .signing: return "AppUpdate.Signing"
            case .uploading: return "AppUpdate.PreparingInstall"
            case .ready: return "AppUpdate.Ready"
            case .installRequested: return "AppUpdate.InstallRequested"
            case let .failed(key): return key
            }
        }
    }
    @Published public private(set) var stage: Stage = .idle
    @Published public private(set) var progress = 0.0
    @Published public private(set) var release: RGUpdateRelease?
    @Published public private(set) var certificateName: String
    @Published public var automaticallyCheck: Bool { didSet { UserDefaults.standard.set(automaticallyCheck, forKey: "Regram.AppUpdate.Check"); if automaticallyCheck { checkAutomatically() } } }
    @Published public var preferredNode: String { didSet { UserDefaults.standard.set(preferredNode, forKey: "Regram.AppUpdate.LCSignNode") } }
    @Published public private(set) var availableNodes = RGLCSignNode.fallback
    @Published public private(set) var activeNode = ""
    @Published public var automaticallyPrepare: Bool { didSet { UserDefaults.standard.set(automaticallyPrepare, forKey: "Regram.AppUpdate.Prepare") } }
    public var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    public var installedBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    public var isConfigured: Bool { !certificateName.isEmpty }
    public var hasPreparedUpdate: Bool { preparedIPA != nil }
    private var operation: Task<Void, Never>?
    private var operationId: UUID?
    private var preparedIPA: URL?
    private var localServer: RGLocalUpdateServer?
    private var installationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var foregroundObserver: NSObjectProtocol?
    private var protectedDataObserver: NSObjectProtocol?
    private var lastCheck: Date = .distantPast
    private var lastAutomaticPreparation: Int64?
    private let directory: URL
    private var credentialIsBusy = false

    private init() {
        let defaults = UserDefaults.standard
        let isCertificateInstall = FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision").path)
        self.automaticallyCheck = defaults.object(forKey: "Regram.AppUpdate.Check") as? Bool ?? isCertificateInstall
        self.automaticallyPrepare = defaults.bool(forKey: "Regram.AppUpdate.Prepare")
        self.preferredNode = defaults.string(forKey: "Regram.AppUpdate.LCSignNode") ?? ""
        self.certificateName = RGUpdateIdentity.load()?.displayName ?? ""
        self.directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RegramUpdates", isDirectory: true)
        // The installed build itself confirms success. Opening itms-services never does.
        if let requested = defaults.string(forKey: "Regram.AppUpdate.RequestedBuild"), requested == installedBuild {
            defaults.removeObject(forKey: "Regram.AppUpdate.RequestedBuild")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    public func start() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                self.restoreCertificate()
                self.checkAutomatically()
            }
        }
        protectedDataObserver = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in self.restoreCertificate() }
        }
        restoreCertificate()
        checkAutomatically()
    }

    private func restoreCertificate() {
        // A launch before the first unlock must not permanently mark a saved
        // certificate as missing. Read again when protected data is available.
        guard !credentialIsBusy, let identity = RGUpdateIdentity.load() else { return }
        certificateName = identity.displayName
    }

    private func checkAutomatically() {
        guard automaticallyCheck, !stage.isBusy, Date().timeIntervalSince(lastCheck) >= 6 * 3600 else { return }
        check()
    }

    private func invalidateInstallation() {
        stopInstallation()
        if let preparedIPA { try? FileManager.default.removeItem(at: preparedIPA) }
        preparedIPA = nil
        if !stage.isBusy { stage = release == nil ? .idle : .available }
    }

    public func importCertificate(_ data: Data, password: String) async throws {
        guard !stage.isBusy, !credentialIsBusy, data.count <= 256 * 1024 else { throw RGUpdateError.invalidCertificate }
        credentialIsBusy = true
        defer { credentialIsBusy = false }
        let path = Bundle.main.bundlePath
        let name: String
        do {
            name = try await Task.detached(priority: .userInitiated) { try RGUpdateSigner.validateCertificate(data, password: password, installedApp: path) }.value
        } catch { throw mapSigningError(error) }
        try RGUpdateKeychain.write(try JSONEncoder().encode(RGUpdateIdentity(p12: data, password: password, name: name)), account: "identity")
        certificateName = name
        invalidateInstallation()
    }

    public func importProfiles(_ data: [Data]) throws {
        guard !stage.isBusy, data.count <= 16, data.allSatisfy({ $0.count <= 256 * 1024 }) else { throw RGUpdateError.invalidProfile }
        try RGUpdateKeychain.write(try JSONEncoder().encode(data), account: "profiles")
        invalidateInstallation()
    }

    public func clearCertificate() throws {
        guard !stage.isBusy, !credentialIsBusy else { return }
        for key in ["identity", "certificate-name", "profiles"] { try RGUpdateKeychain.write(nil, account: key) }
        certificateName = ""
        invalidateInstallation()
    }

    public func check() {
        guard !stage.isBusy, !credentialIsBusy else { return }
        operation?.cancel()
        let id = UUID(); operationId = id; stage = .checking; lastCheck = Date()
        operation = Task {
            do {
                let delegate = RGUpdateNetworkDelegate(service: nil, maximumSize: 1024 * 1024)
                let session = makeSession(delegate)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/RegramDev/Regram-ios/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Regram/\(installedVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1024 * 1024 else { throw RGUpdateError.network }
                let latest = try RGUpdateRelease.parseGitHub(data)
                guard operationId == id else { return }
                if latest.isNewer(version: installedVersion, build: installedBuild) {
                    if release != latest { invalidateInstallation() }
                    release = latest; stage = preparedIPA == nil ? .available : .ready
                    rgAvailableAppUpdate.set(latest)
                    if automaticallyPrepare, isConfigured, lastAutomaticPreparation != latest.build {
                        lastAutomaticPreparation = latest.build
                        prepare()
                    }
                } else { release = nil; invalidateInstallation(); stage = .upToDate; rgAvailableAppUpdate.set(nil) }
            } catch { finishError(error, id: id) }
        }
    }

    public func prepare() {
        guard !stage.isBusy, !credentialIsBusy, let release else { return }
        guard isConfigured else { stage = .failed(RGUpdateError.notConfigured.localizationKey); return }
        operation?.cancel()
        let id = UUID(); operationId = id; invalidateInstallation(); stage = .downloading; progress = 0.0
        operation = Task {
            let operationDirectory = directory.appendingPathComponent(id.uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: operationDirectory) }
            do {
                try FileManager.default.createDirectory(at: operationDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                let delegate = RGUpdateNetworkDelegate(service: nil, maximumSize: release.size)
                delegate.progress = { value in Task { @MainActor in if self.operationId == id { self.progress = value } } }
                let downloadSession = makeSession(delegate)
                defer { downloadSession.invalidateAndCancel() }
                let (temporary, response) = try await downloadSession.download(from: release.downloadURL)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RGUpdateError.network }
                let downloaded = operationDirectory.appendingPathComponent("release.ipa")
                try FileManager.default.moveItem(at: temporary, to: downloaded)
                let actualSize = try FileManager.default.attributesOfItem(atPath: downloaded.path)[.size] as? NSNumber
                guard actualSize?.int64Value == release.size else { throw RGUpdateError.hashMismatch }
                let hash = try await Task.detached { try Self.hashFile(downloaded) }.value
                guard hash == release.sha256 else { throw RGUpdateError.hashMismatch }
                guard let identity = RGUpdateIdentity.load() else { throw RGUpdateError.notConfigured }
                let profiles = try JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8))
                let signed = operationDirectory.appendingPathComponent("signed.ipa")
                let installedPath = Bundle.main.bundlePath
                guard operationId == id else { return }
                stage = .signing
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.prepareIPA(downloaded.path, output: signed.path, installedApp: installedPath, certificate: identity.p12, password: identity.password, profiles: profiles, expectedVersion: release.version, expectedBuild: String(release.build))
                    }.value
                } catch { throw mapSigningError(error) }
                try Task.checkCancellation()
                guard operationId == id else { return }
                let prepared = directory.appendingPathComponent("signed-" + id.uuidString + ".ipa")
                try FileManager.default.moveItem(at: signed, to: prepared)
                preparedIPA = prepared; progress = 1.0; stage = .ready
                // A foreground prompt asks the user to launch Apple's installer.
                rgAvailableAppUpdate.set(nil); rgAvailableAppUpdate.set(release)
            } catch { finishError(error, id: id) }
        }
    }

    public func install() {
        guard !stage.isBusy, let release, let preparedIPA else { return }
        stopInstallation()
        let id = UUID(); operationId = id; stage = .uploading
        installationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Regram.InstallUpdate") { [weak self] in
            Task { @MainActor in self?.stopInstallation() }
        }
        operation = Task {
            do {
                let server = try RGLocalUpdateServer(fileURL: preparedIPA)
                localServer = server
                server.closed = { Task { @MainActor in if self.operationId == id { self.stopInstallation() } } }
                let packageURL = try await server.start()
                try Task.checkCancellation()
                let delegate = RGUpdateNetworkDelegate(service: URL(string: "https://support.lcsignx.com")!, maximumSize: 1024 * 1024)
                let session = makeSession(delegate)
                defer { session.invalidateAndCancel() }
                let configuration = URL(string: "https://support.lcsignx.com/install/services")!
                if let (data, response) = try? await session.data(from: configuration), (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1024 * 1024,
                   let nodes = try? RGLCSignNode.parse(data), !nodes.isEmpty { availableNodes = nodes }
                let nodes = availableNodes.sorted { a, b in
                    if a.code == preferredNode { return b.code != preferredNode }
                    if b.code == preferredNode { return false }
                    return a.priority < b.priority
                }
                let body = try RGLCSignNode.manifestRequest(packageURL: packageURL, bundleId: Bundle.main.bundleIdentifier ?? "", build: String(release.build))
                var installationURL: URL?
                for node in nodes {
                    try Task.checkCancellation()
                    activeNode = node.name
                    do {
                        var request = URLRequest(url: node.baseURL.appendingPathComponent("ota/manifest"))
                        request.timeoutInterval = 12
                        request.httpMethod = "POST"
                        request.httpBody = body
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        let (data, response) = try await session.data(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1024 * 1024 else { throw RGUpdateError.network }
                        struct ManifestResponse: Decodable { let token: String }
                        let hosted = try JSONDecoder().decode(ManifestResponse.self, from: data)
                        // LCSign also constructs the URL on the chosen node. The API may
                        // advertise support.lcsignx.com, whose token database is separate.
                        let manifestURL = try node.manifestURL(token: hosted.token)
                        let url = try RGLCSignNode.installationURL(manifest: manifestURL)
                        let (manifestData, manifestResponse) = try await session.data(from: manifestURL)
                        guard (manifestResponse as? HTTPURLResponse)?.statusCode == 200, manifestData.count <= 1024 * 1024 else { throw RGUpdateError.invalidManifest }
                        try RGLCSignNode.validateManifest(manifestData, bundleId: Bundle.main.bundleIdentifier ?? "", build: String(release.build), packageURL: packageURL)
                        installationURL = url
                        break
                    } catch {
                        try Task.checkCancellation()
                    }
                }
                try Task.checkCancellation()
                guard operationId == id, let installationURL else { throw RGUpdateError.network }
                UIApplication.shared.open(installationURL, options: [:]) { opened in
                    Task { @MainActor in
                        guard self.operationId == id else { return }
                        if opened { UserDefaults.standard.set(String(release.build), forKey: "Regram.AppUpdate.RequestedBuild"); self.stage = .installRequested }
                        else { self.stopInstallation(); self.stage = .failed(RGUpdateError.invalidManifest.localizationKey) }
                    }
                }
            } catch {
                if operationId == id { stopInstallation() }
                finishError(error, id: id)
            }
        }
    }

    private func stopInstallation() {
        let server = localServer; localServer = nil; server?.stop()
        if installationBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(installationBackgroundTask)
            installationBackgroundTask = .invalid
        }
    }

    public func cancel() {
        operationId = nil; operation?.cancel(); operation = nil
        stopInstallation()
        stage = preparedIPA != nil ? .ready : (release == nil ? .idle : .available); progress = 0.0
    }

    public func claimPrompt(for release: RGUpdateRelease) -> Bool {
        let key = stage == .ready ? "Regram.AppUpdate.PromptedReadyBuild" : "Regram.AppUpdate.PromptedBuild"
        guard UserDefaults.standard.string(forKey: key) != String(release.build) else { return false }
        UserDefaults.standard.set(String(release.build), forKey: key)
        return true
    }

    private func finishError(_ error: Error, id: UUID) {
        guard operationId == id else { return }
        if error is CancellationError { stage = release == nil ? .idle : .available }
        else { stage = .failed((error as? RGUpdateError ?? .network).localizationKey) }
    }

    private func mapSigningError(_ error: Error) -> RGUpdateError {
        let error = error as NSError
        guard error.domain == "RGUpdateSigner" else { return .signing }
        switch error.code {
        case 1: return .invalidCertificate
        case 2: return .certificateMismatch
        case 3: return .invalidProfile
        case 4: return .invalidArchive
        case 5: return .identityMismatch
        default: return .signing
        }
    }

    private func makeSession(_ delegate: RGUpdateNetworkDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 900
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    nonisolated private static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

}

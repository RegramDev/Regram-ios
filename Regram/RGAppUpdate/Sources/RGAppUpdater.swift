// MARK: Regram
import Foundation
import UIKit
import Combine
import SwiftSignalKit
import RGUpdateSigner

public let rgAvailableAppUpdate = ValuePromise<RGUpdateRelease?>(nil, ignoreRepeated: true)

private final class RGUpdateNetworkDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    let service: URL?
    let maximumSize: Int64
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
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(response.expectedContentLength > maximumSize ? .cancel : .allow)
    }
}

@MainActor public final class RGAppUpdater: ObservableObject {
    public static let shared = RGAppUpdater()
    public enum Stage: Equatable {
        case idle, restoring, checking, available, upToDate, validating, downloading, signing, uploading, ready, installRequested, installing, trollStoreReceived, failed(String)
        public var isBusy: Bool { [.restoring, .checking, .validating, .downloading, .signing, .uploading, .installing].contains(self) }
        public var localizationKey: String {
            switch self {
            case .idle: return "AppUpdate.Check"
            case .restoring: return "AppUpdate.Restoring"
            case .checking: return "AppUpdate.Checking"
            case .available: return "AppUpdate.Available"
            case .upToDate: return "AppUpdate.UpToDate"
            case .validating: return "AppUpdate.Validating"
            case .downloading: return "AppUpdate.Downloading"
            case .signing: return "AppUpdate.Signing"
            case .uploading: return "AppUpdate.PreparingInstall"
            case .ready: return "AppUpdate.Ready"
            case .installRequested: return "AppUpdate.InstallRequested"
            case .installing: return "AppUpdate.InstallReading"
            case .trollStoreReceived: return "AppUpdate.TrollStoreReceived"
            case let .failed(key): return key
            }
        }
    }
    @Published public private(set) var stage: Stage = .idle
    @Published public private(set) var progress = 0.0
    @Published public private(set) var downloadedBytes: Int64 = 0
    @Published public private(set) var hasDownloadedUpdate = false
    @Published public private(set) var failure: RGUpdateError?
    @Published public private(set) var release: RGUpdateRelease?
    @Published public private(set) var certificateName: String
    @Published public private(set) var savedProfileCount: Int
    @Published public var automaticallyCheck: Bool { didSet { UserDefaults.standard.set(automaticallyCheck, forKey: "Regram.AppUpdate.Check"); if automaticallyCheck { checkAutomatically() } } }
    @Published public var preferredNode: String { didSet { UserDefaults.standard.set(preferredNode, forKey: "Regram.AppUpdate.LCSignNode") } }
    @Published public private(set) var availableNodes = RGLCSignNode.fallback
    @Published public private(set) var activeNode = ""
    @Published public var automaticallyPrepare: Bool { didSet { UserDefaults.standard.set(automaticallyPrepare, forKey: "Regram.AppUpdate.Prepare") } }
    @Published public var installationMethod: RGUpdateInstallationMethod {
        didSet {
            guard oldValue != installationMethod else { return }
            UserDefaults.standard.set(installationMethod.rawValue, forKey: "Regram.AppUpdate.InstallationMethod")
            operationId = nil; operation?.cancel(); stopInstallation()
            preparedIPA = nil; failure = nil; activeNode = ""
            lastAutomaticPreparation = nil; didRestoreCache = false
            stage = release == nil ? .idle : .available
            activate()
        }
    }
    public var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    public var installedBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    public var isConfigured: Bool { installationMethod == .trollStore || !certificateName.isEmpty }
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
    private let cache: RGUpdateCache
    private var credentialIsBusy = false
    private var didRestoreCache = false
    private var installationWatchdog: Task<Void, Never>?
    private var packageReadStarted = false

    private init() {
        let defaults = UserDefaults.standard
        let method = defaults.string(forKey: "Regram.AppUpdate.InstallationMethod").flatMap(RGUpdateInstallationMethod.init(rawValue:)) ?? .detected(bundleURL: Bundle.main.bundleURL)
        self.installationMethod = method
        let isCertificateInstall = FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision").path)
        self.automaticallyCheck = defaults.object(forKey: "Regram.AppUpdate.Check") as? Bool ?? (isCertificateInstall || method == .trollStore)
        self.automaticallyPrepare = defaults.bool(forKey: "Regram.AppUpdate.Prepare")
        self.preferredNode = defaults.string(forKey: "Regram.AppUpdate.LCSignNode") ?? ""
        self.certificateName = RGUpdateIdentity.load()?.displayName ?? ""
        self.savedProfileCount = (try? JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8)).count) ?? 0
        self.directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RegramUpdateOperations", isDirectory: true)
        self.cache = RGUpdateCache(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RegramUpdates", isDirectory: true))
        // The installed build itself confirms success. Opening itms-services never does.
        if let requested = defaults.string(forKey: "Regram.AppUpdate.RequestedBuild"), requested == installedBuild {
            defaults.removeObject(forKey: "Regram.AppUpdate.RequestedBuild")
        }
        // Only unfinished operation directories are transient. Verified IPA
        // downloads and signed packages live in Application Support.
        try? FileManager.default.removeItem(at: directory)
    }

    public func start() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                self.activate()
            }
        }
        protectedDataObserver = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in self.activate() }
        }
        activate()
    }

    private func activate() {
        restoreCertificate()
        if !didRestoreCache, UIApplication.shared.isProtectedDataAvailable, !stage.isBusy, !credentialIsBusy {
            didRestoreCache = true
            let id = UUID(); operationId = id; stage = .restoring
            let method = installationMethod
            let fingerprint = method == .certificate ? signingFingerprint() : nil
            let version = installedVersion, build = installedBuild, cache = self.cache
            operation = Task {
                do {
                    let state = try await Task.detached(priority: .utility) { try cache.load(installedVersion: version, installedBuild: build, signer: fingerprint) }.value
                    guard operationId == id else { return }
                    if let state {
                        release = state.release; preparedIPA = method == .trollStore ? state.downloaded : state.prepared; hasDownloadedUpdate = state.downloaded != nil
                        downloadedBytes = state.downloaded == nil ? 0 : state.release.size
                        progress = state.downloaded == nil ? 0 : 1
                        stage = preparedIPA == nil ? .available : .ready
                        rgAvailableAppUpdate.set(state.release)
                    } else { stage = .idle }
                    checkAutomatically()
                } catch {
                    guard operationId == id else { return }
                    didRestoreCache = false; stage = .idle
                    checkAutomatically()
                }
            }
        } else { checkAutomatically() }
    }

    private func signingFingerprint() -> String? {
        guard let identity = RGUpdateIdentity.load(),
              let profiles = try? JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8)) else { return nil }
        return RGUpdateCache.signerFingerprint(certificate: identity.p12, profiles: profiles, bundleId: Bundle.main.bundleIdentifier ?? "", installedBuild: installedBuild)
    }

    private func restoreCertificate() {
        // A launch before the first unlock must not permanently mark a saved
        // certificate as missing. Read again when protected data is available.
        guard !credentialIsBusy, let identity = RGUpdateIdentity.load() else { return }
        certificateName = identity.displayName
        savedProfileCount = (try? JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8)).count) ?? 0
    }

    private func checkAutomatically() {
        guard automaticallyCheck, !stage.isBusy, Date().timeIntervalSince(lastCheck) >= 6 * 3600 else { return }
        check()
    }

    private func invalidateInstallation(cancelOperation: Bool = true) {
        if cancelOperation { operationId = nil; operation?.cancel() }
        stopInstallation()
        failure = nil
        try? cache.discardSigned()
        preparedIPA = nil
        if cancelOperation || !stage.isBusy { stage = release == nil ? .idle : .available }
    }

    public func importCertificate(_ data: Data, password: String, profiles importedProfiles: [Data] = []) async throws {
        guard !stage.isBusy, !credentialIsBusy, data.count <= 256 * 1024, importedProfiles.count <= 16, importedProfiles.allSatisfy({ $0.count <= 256 * 1024 }) else { throw RGUpdateError.invalidCertificate }
        credentialIsBusy = true
        defer { credentialIsBusy = false }
        let path = Bundle.main.bundlePath
        let name: String
        let installedProfiles: [Data]
        let previousProfiles = RGUpdateKeychain.read("profiles")
        let existing = try JSONDecoder().decode([Data].self, from: previousProfiles ?? Data("[]".utf8))
        do {
            (name, installedProfiles) = try await Task.detached(priority: .userInitiated) {
                let name = try RGUpdateSigner.validateCertificate(data, password: password, installedApp: path)
                if !importedProfiles.isEmpty { try RGUpdateSigner.validateProfiles(importedProfiles) }
                let profiles = try RGUpdateSigner.installedProfiles(path, certificate: data, password: password)
                try RGUpdateSigner.validateInstalledApp(path, certificate: data, password: password, profiles: existing + importedProfiles + profiles)
                return (name, profiles)
            }.value
        } catch { throw mapSigningError(error) }
        try saveProfiles(importedProfiles + installedProfiles)
        do {
            try RGUpdateKeychain.write(try JSONEncoder().encode(RGUpdateIdentity(p12: data, password: password, name: name)), account: "identity")
        } catch {
            try? RGUpdateKeychain.write(previousProfiles, account: "profiles")
            savedProfileCount = existing.count
            throw error
        }
        certificateName = name
        invalidateInstallation()
    }

    public func importProfiles(_ data: [Data]) async throws {
        guard !stage.isBusy, !credentialIsBusy, !data.isEmpty, data.count <= 16, data.allSatisfy({ $0.count <= 256 * 1024 }) else { throw RGUpdateError.invalidProfile }
        credentialIsBusy = true
        defer { credentialIsBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) { try RGUpdateSigner.validateProfiles(data) }.value
        } catch { throw mapSigningError(error) }
        try saveProfiles(data)
        invalidateInstallation()
    }

    private func saveProfiles(_ data: [Data]) throws {
        let existing = try JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8))
        var merged = existing
        for profile in data where !merged.contains(profile) { merged.append(profile) }
        guard merged.count <= 64 else { throw RGUpdateError.profileLimit }
        try RGUpdateKeychain.write(try JSONEncoder().encode(merged), account: "profiles")
        savedProfileCount = merged.count
    }

    public func clearCertificate() throws {
        guard !stage.isBusy, !credentialIsBusy else { return }
        for key in ["identity", "certificate-name", "profiles"] { try RGUpdateKeychain.write(nil, account: key) }
        certificateName = ""
        savedProfileCount = 0
        invalidateInstallation()
    }

    public func check() {
        guard !stage.isBusy, !credentialIsBusy else { return }
        operation?.cancel()
        let id = UUID(); operationId = id; failure = nil; stage = .checking; lastCheck = Date()
        operation = Task {
            do {
                let delegate = RGUpdateNetworkDelegate(service: nil, maximumSize: 1024 * 1024)
                let session = makeSession(delegate)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/RegramDev/Regram-ios/releases/latest")!)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Regram/\(installedVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1024 * 1024 else { throw RGUpdateError.network }
                let latest = try RGUpdateRelease.parseGitHub(data)
                guard operationId == id else { return }
                if latest.isNewer(version: installedVersion, build: installedBuild) {
                    if release?.hasSameArtifact(as: latest) != true {
                        invalidateInstallation(cancelOperation: false)
                        hasDownloadedUpdate = false; downloadedBytes = 0; progress = 0
                    }
                    let cache = self.cache
                    try await Task.detached { try cache.select(latest) }.value
                    guard operationId == id else { return }
                    release = latest; stage = preparedIPA == nil ? .available : .ready
                    rgAvailableAppUpdate.set(latest)
                    if automaticallyPrepare, isConfigured, preparedIPA == nil, lastAutomaticPreparation != latest.build {
                        lastAutomaticPreparation = latest.build
                        prepare()
                    }
                } else {
                    release = nil; invalidateInstallation(cancelOperation: false); try cache.clear(); hasDownloadedUpdate = false
                    stage = .upToDate; rgAvailableAppUpdate.set(nil)
                }
            } catch { finishError(error, id: id) }
        }
    }

    public func prepare() {
        guard !stage.isBusy, !credentialIsBusy, let release else { return }
        guard isConfigured else { failure = .notConfigured; stage = .failed(RGUpdateError.notConfigured.localizationKey); return }
        operation?.cancel()
        let id = UUID(); operationId = id; stopInstallation(); failure = nil; stage = .validating
        if installationMethod == .trollStore {
            prepareTrollStore(release: release, id: id)
            return
        }
        operation = Task {
            let operationDirectory = directory.appendingPathComponent(id.uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: operationDirectory) }
            do {
                guard let identity = RGUpdateIdentity.load() else { throw RGUpdateError.notConfigured }
                let installedPath = Bundle.main.bundlePath
                let installedProfiles: [Data]
                do {
                    installedProfiles = try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.installedProfiles(installedPath, certificate: identity.p12, password: identity.password)
                    }.value
                } catch { throw mapSigningError(error) }
                try Task.checkCancellation()
                guard operationId == id else { return }
                try saveProfiles(installedProfiles)
                let profiles = try JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8))
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.validateInstalledApp(installedPath, certificate: identity.p12, password: identity.password, profiles: profiles)
                    }.value
                } catch { throw mapSigningError(error) }
                try Task.checkCancellation()
                guard operationId == id else { return }
                try FileManager.default.createDirectory(at: operationDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                let cache = self.cache
                let fingerprint = RGUpdateCache.signerFingerprint(certificate: identity.p12, profiles: profiles, bundleId: Bundle.main.bundleIdentifier ?? "", installedBuild: installedBuild)
                let version = installedVersion, build = installedBuild
                let state = try await Task.detached { try cache.load(installedVersion: version, installedBuild: build, signer: fingerprint) }.value
                try Task.checkCancellation()
                guard operationId == id else { return }
                if let state, state.release.hasSameArtifact(as: release), let prepared = state.prepared {
                    preparedIPA = prepared; hasDownloadedUpdate = state.downloaded != nil; progress = 1; downloadedBytes = release.size; stage = .ready
                    return
                }
                let downloaded: URL
                if let state, state.release.hasSameArtifact(as: release), let existing = state.downloaded {
                    downloaded = existing; hasDownloadedUpdate = true; downloadedBytes = release.size; progress = 1
                } else {
                    stage = .downloading; progress = 0; downloadedBytes = 0; hasDownloadedUpdate = false
                    let temporary = operationDirectory.appendingPathComponent("release.ipa")
                    let download = RGUpdateDownload(destination: temporary, expectedSize: release.size) { value, bytes in
                        Task { @MainActor in
                            guard self.operationId == id, self.stage == .downloading else { return }
                            self.progress = value; self.downloadedBytes = bytes
                        }
                    }
                    try await download.download(from: release.downloadURL, configuration: networkConfiguration())
                    try Task.checkCancellation()
                    guard operationId == id else { return }
                    downloaded = try await Task.detached { try cache.saveDownloaded(temporary, release: release) }.value
                    hasDownloadedUpdate = true
                }
                let signed = operationDirectory.appendingPathComponent("signed.ipa")
                guard operationId == id else { return }
                stage = .signing
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.prepareIPA(downloaded.path, output: signed.path, installedApp: installedPath, certificate: identity.p12, password: identity.password, profiles: profiles, expectedVersion: release.version, expectedBuild: String(release.build))
                    }.value
                } catch { throw mapSigningError(error) }
                try Task.checkCancellation()
                guard operationId == id else { return }
                let prepared = try await Task.detached { try cache.saveSigned(signed, release: release, signer: fingerprint) }.value
                guard operationId == id else { return }
                preparedIPA = prepared; progress = 1.0; stage = .ready
                // A foreground prompt asks the user to launch Apple's installer.
                rgAvailableAppUpdate.set(nil); rgAvailableAppUpdate.set(release)
            } catch { finishError(error, id: id) }
        }
    }

    private func prepareTrollStore(release: RGUpdateRelease, id: UUID) {
        operation = Task {
            let operationDirectory = directory.appendingPathComponent(id.uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: operationDirectory) }
            do {
                let cache = self.cache, version = installedVersion, build = installedBuild
                let state = try await Task.detached { try cache.load(installedVersion: version, installedBuild: build, signer: nil) }.value
                try Task.checkCancellation()
                guard operationId == id else { return }
                let downloaded: URL
                if let state, state.release.hasSameArtifact(as: release), let existing = state.downloaded {
                    downloaded = existing
                } else {
                    try FileManager.default.createDirectory(at: operationDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                    stage = .downloading; progress = 0; downloadedBytes = 0; hasDownloadedUpdate = false
                    let temporary = operationDirectory.appendingPathComponent("release.ipa")
                    let download = RGUpdateDownload(destination: temporary, expectedSize: release.size) { value, bytes in
                        Task { @MainActor in
                            guard self.operationId == id, self.stage == .downloading else { return }
                            self.progress = value; self.downloadedBytes = bytes
                        }
                    }
                    try await download.download(from: release.downloadURL, configuration: networkConfiguration())
                    try Task.checkCancellation()
                    guard operationId == id else { return }
                    downloaded = try await Task.detached { try cache.saveDownloaded(temporary, release: release) }.value
                }
                try Task.checkCancellation()
                guard operationId == id else { return }
                hasDownloadedUpdate = true; progress = 1; downloadedBytes = release.size; stage = .validating
                let installedPath = Bundle.main.bundlePath
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.validateTrollStoreIPA(downloaded.path, installedApp: installedPath, expectedVersion: release.version, expectedBuild: String(release.build))
                    }.value
                } catch { throw mapSigningError(error) }
                try Task.checkCancellation()
                guard operationId == id else { return }
                preparedIPA = downloaded; stage = .ready
                rgAvailableAppUpdate.set(nil); rgAvailableAppUpdate.set(release)
            } catch { finishError(error, id: id) }
        }
    }

    public func install() {
        guard !stage.isBusy, let release, let preparedIPA else { return }
        stopInstallation()
        let id = UUID(); operationId = id; failure = nil; stage = .uploading
        packageReadStarted = false
        installationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Regram.InstallUpdate") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stopInstallation()
                if self.operationId == id, self.stage != .trollStoreReceived { self.failure = .installationChannelEnded; self.stage = .failed(RGUpdateError.installationChannelEnded.localizationKey) }
            }
        }
        if installationMethod == .trollStore {
            installTrollStore(release: release, preparedIPA: preparedIPA, id: id)
            return
        }
        operation = Task {
            do {
                guard let identity = RGUpdateIdentity.load() else { throw RGUpdateError.notConfigured }
                let profiles = try JSONDecoder().decode([Data].self, from: RGUpdateKeychain.read("profiles") ?? Data("[]".utf8))
                let installedPath = Bundle.main.bundlePath
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.validateInstalledApp(installedPath, certificate: identity.p12, password: identity.password, profiles: profiles)
                    }.value
                } catch { throw mapSigningError(error) }
                let cache = self.cache, version = installedVersion, build = installedBuild
                let fingerprint = RGUpdateCache.signerFingerprint(certificate: identity.p12, profiles: profiles, bundleId: Bundle.main.bundleIdentifier ?? "", installedBuild: build)
                let cached = try await Task.detached { try cache.load(installedVersion: version, installedBuild: build, signer: fingerprint) }.value
                try Task.checkCancellation()
                guard operationId == id else { return }
                guard let cached, cached.release.hasSameArtifact(as: release), cached.prepared == preparedIPA else {
                    self.preparedIPA = nil; hasDownloadedUpdate = cached?.downloaded != nil
                    throw RGUpdateError.cache
                }
                let server = try RGLocalUpdateServer(fileURL: preparedIPA)
                localServer = server
                server.closed = { Task { @MainActor in
                    guard self.operationId == id else { return }
                    self.stopInstallation()
                    if self.stage == .installRequested || self.stage == .installing {
                        self.failure = .installationChannelEnded; self.stage = .failed(RGUpdateError.installationChannelEnded.localizationKey)
                    }
                } }
                server.packageRequested = { Task { @MainActor in
                    guard self.operationId == id else { return }
                    self.packageReadStarted = true; self.installationWatchdog?.cancel(); self.installationWatchdog = nil
                    self.failure = nil; self.stage = .installing
                } }
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
                        if opened {
                            UserDefaults.standard.set(String(release.build), forKey: "Regram.AppUpdate.RequestedBuild")
                            if !self.packageReadStarted {
                                self.stage = .installRequested
                                self.watchInstallationStart(id: id)
                            }
                        }
                        else { self.stopInstallation(); self.failure = .installationRejected; self.stage = .failed(RGUpdateError.installationRejected.localizationKey) }
                    }
                }
            } catch {
                if operationId == id { stopInstallation() }
                finishError(error, id: id)
            }
        }
    }

    private func installTrollStore(release: RGUpdateRelease, preparedIPA: URL, id: UUID) {
        operation = Task {
            do {
                let cache = self.cache, version = installedVersion, build = installedBuild
                let state = try await Task.detached { try cache.load(installedVersion: version, installedBuild: build, signer: nil) }.value
                guard let state, state.release.hasSameArtifact(as: release), state.downloaded == preparedIPA else { throw RGUpdateError.cache }
                let installedPath = Bundle.main.bundlePath
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RGUpdateSigner.validateTrollStoreIPA(preparedIPA.path, installedApp: installedPath, expectedVersion: release.version, expectedBuild: String(release.build))
                    }.value
                } catch { throw mapSigningError(error) }
                try Task.checkCancellation()
                guard operationId == id else { return }
                let server = try RGLocalUpdateServer(fileURL: preparedIPA)
                localServer = server
                server.closed = { Task { @MainActor in
                    guard self.operationId == id else { return }
                    self.stopInstallation()
                    if self.stage == .installRequested || self.stage == .installing {
                        self.failure = .installationChannelEnded; self.stage = .failed(RGUpdateError.installationChannelEnded.localizationKey)
                    }
                } }
                server.packageRequested = { Task { @MainActor in
                    guard self.operationId == id else { return }
                    self.packageReadStarted = true; self.installationWatchdog?.cancel(); self.installationWatchdog = nil
                    self.failure = nil; self.stage = .installing
                } }
                server.packageDelivered = { Task { @MainActor in
                    guard self.operationId == id else { return }
                    self.stage = .trollStoreReceived; self.failure = nil
                    self.stopInstallation()
                } }
                let packageURL = try await server.start()
                try Task.checkCancellation()
                guard operationId == id else { return }
                let url = try RGTrollStoreInstallation.installationURL(packageURL: packageURL)
                guard UIApplication.shared.canOpenURL(url) else { throw RGUpdateError.trollStoreUnavailable }
                UIApplication.shared.open(url, options: [:]) { opened in
                    Task { @MainActor in
                        guard self.operationId == id else { return }
                        if opened {
                            UserDefaults.standard.set(String(release.build), forKey: "Regram.AppUpdate.RequestedBuild")
                            if !self.packageReadStarted { self.stage = .installRequested; self.watchInstallationStart(id: id) }
                        } else {
                            self.stopInstallation(); self.failure = .trollStoreUnavailable; self.stage = .failed(RGUpdateError.trollStoreUnavailable.localizationKey)
                        }
                    }
                }
            } catch {
                if operationId == id { stopInstallation() }
                finishError(error, id: id)
            }
        }
    }

    private func stopInstallation() {
        installationWatchdog?.cancel(); installationWatchdog = nil
        let server = localServer; localServer = nil; server?.stop()
        if installationBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(installationBackgroundTask)
            installationBackgroundTask = .invalid
        }
    }

    private func watchInstallationStart(id: UUID) {
        installationWatchdog?.cancel()
        installationWatchdog = Task {
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard operationId == id, !packageReadStarted, stage == .installRequested else { return }
            let error: RGUpdateError = installationMethod == .trollStore ? .trollStoreNotStarted : .installationNotStarted
            failure = error; stage = .failed(error.localizationKey)
            // Keep the channel alive for a pending system dialog. A retry uses
            // the same signed cache, without another download or signature.
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
        else {
            let failure = error as? RGUpdateError ?? ((error as NSError).domain == NSCocoaErrorDomain ? .cache : .network)
            self.failure = failure; stage = .failed(failure.localizationKey)
        }
    }

    private func mapSigningError(_ error: Error) -> RGUpdateError {
        let error = error as NSError
        guard error.domain == "RGUpdateSigner" else { return .signing }
        switch error.code {
        case 1: return .invalidCertificate
        case 2: return .certificateMismatch
        case 3:
            if let reason = error.userInfo["profileReason"] as? String {
                return .profileMismatch(bundle: error.userInfo["bundleName"] as? String ?? "", reason: reason, entitlement: error.userInfo["entitlement"] as? String ?? "")
            }
            return .invalidProfile
        case 4: return .invalidArchive
        case 5: return .identityMismatch
        default: return .signing
        }
    }

    private func makeSession(_ delegate: RGUpdateNetworkDelegate) -> URLSession {
        return URLSession(configuration: networkConfiguration(), delegate: delegate, delegateQueue: nil)
    }

    private func networkConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 900
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return config
    }

}

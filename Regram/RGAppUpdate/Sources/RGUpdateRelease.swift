// MARK: Regram
import Foundation

public struct RGUpdateRelease: Equatable, Codable, Sendable {
    public let version: String
    public let build: Int64
    public let downloadURL: URL
    public let sha256: String
    public let size: Int64
    public let notes: String
    public var releaseURL: URL {
        URL(string: "https://github.com/RegramDev/Regram-ios/releases/tag")!.appendingPathComponent("v\(version)-b\(build)")
    }

    public static func parseGitHub(_ data: Data) throws -> RGUpdateRelease {
        struct Asset: Decodable { let name: String; let size: Int64; let digest: String?; let browser_download_url: String }
        struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool; let body: String?; let assets: [Asset] }
        let value = try JSONDecoder().decode(Release.self, from: data)
        guard !value.draft, !value.prerelease else { throw RGUpdateError.invalidRelease }
        let pattern = #"^Regram-([0-9]+(?:\.[0-9]+){1,3})-b([1-9][0-9]*)\.ipa$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = value.assets.compactMap { asset -> (Asset, NSTextCheckingResult)? in
            guard let match = regex.firstMatch(in: asset.name, range: NSRange(asset.name.startIndex..., in: asset.name)) else { return nil }
            return (asset, match)
        }
        guard matches.count == 1 else { throw RGUpdateError.invalidRelease }
        let (asset, match) = matches[0]
        let name = asset.name as NSString
        let version = name.substring(with: match.range(at: 1))
        guard let build = Int64(name.substring(with: match.range(at: 2))), value.tag_name == "v\(version)-b\(build)",
              let url = URL(string: asset.browser_download_url), validHTTPS(url),
              url.host?.lowercased() == "github.com", url.path.hasPrefix("/RegramDev/Regram-ios/releases/download/"),
              url.lastPathComponent == asset.name, let digest = asset.digest, digest.hasPrefix("sha256:") else { throw RGUpdateError.invalidRelease }
        let hash = String(digest.dropFirst(7)).lowercased()
        guard hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), asset.size > 0, asset.size <= 256 * 1024 * 1024 else { throw RGUpdateError.invalidRelease }
        return RGUpdateRelease(version: version, build: build, downloadURL: url, sha256: hash, size: asset.size, notes: String((value.body ?? "").prefix(12000)))
    }

    public func isNewer(version: String, build: String) -> Bool {
        guard let installedBuild = Int64(build) else { return false }
        let comparison = self.version.compare(version, options: .numeric)
        return comparison == .orderedDescending || (comparison == .orderedSame && self.build > installedBuild)
    }

    public func hasSameArtifact(as other: RGUpdateRelease) -> Bool {
        return version == other.version && build == other.build && downloadURL == other.downloadURL && sha256 == other.sha256 && size == other.size
    }

    func validateCachedMetadata() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v\(version)-b\(build)", "draft": false, "prerelease": false, "body": notes,
            "assets": [["name": "Regram-\(version)-b\(build).ipa", "size": size, "digest": "sha256:" + sha256, "browser_download_url": downloadURL.absoluteString]]
        ])
        guard try Self.parseGitHub(data) == self else { throw RGUpdateError.invalidRelease }
    }

    public static func validHTTPS(_ url: URL) -> Bool {
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil && url.fragment == nil
    }

}

public enum RGUpdateError: Error {
    case invalidRelease, invalidManifest, network, hashMismatch, notConfigured, keychain, invalidCertificate, certificateMismatch, invalidProfile, invalidArchive, identityMismatch, signing, cancelled
    case profileMismatch(bundle: String, reason: String, entitlement: String)
    case profileLimit
    case cache, installationNotStarted, installationRejected, installationChannelEnded, trollStoreUnavailable, trollStoreNotStarted

    public var profileBundle: String? {
        if case let .profileMismatch(bundle, _, _) = self, !bundle.isEmpty { return bundle }
        return nil
    }

    public var profileEntitlement: String? {
        if case let .profileMismatch(_, _, entitlement) = self, !entitlement.isEmpty { return entitlement }
        return nil
    }

    public var localizationKey: String {
        switch self {
        case .invalidRelease: return "AppUpdate.InvalidRelease"
        case .invalidManifest: return "AppUpdate.InvalidManifest"
        case .network: return "AppUpdate.NetworkError"
        case .hashMismatch: return "AppUpdate.HashMismatch"
        case .notConfigured: return "AppUpdate.NotConfigured"
        case .keychain: return "AppUpdate.KeychainError"
        case .invalidCertificate: return "AppUpdate.InvalidCertificate"
        case .certificateMismatch: return "AppUpdate.CertificateMismatch"
        case .invalidProfile: return "AppUpdate.InvalidProfile"
        case .invalidArchive: return "AppUpdate.InvalidArchive"
        case .identityMismatch: return "AppUpdate.IdentityMismatch"
        case .signing: return "AppUpdate.SigningFailed"
        case .cancelled: return "AppUpdate.Cancelled"
        case let .profileMismatch(_, reason, _):
            switch reason {
            case "missing": return "AppUpdate.ProfileMissing"
            case "unreadable": return "AppUpdate.ProfileUnreadable"
            case "expired": return "AppUpdate.ProfileExpired"
            case "certificate": return "AppUpdate.ProfileCertificateMismatch"
            case "applicationIdentifier": return "AppUpdate.ProfileAppIDMismatch"
            case "entitlement": return "AppUpdate.ProfileEntitlementMismatch"
            case "installedEntitlements": return "AppUpdate.InstalledEntitlementsInvalid"
            default: return "AppUpdate.InvalidProfile"
            }
        case .profileLimit: return "AppUpdate.ProfileLimit"
        case .cache: return "AppUpdate.CacheError"
        case .installationNotStarted: return "AppUpdate.InstallationNotStarted"
        case .installationRejected: return "AppUpdate.InstallationRejected"
        case .installationChannelEnded: return "AppUpdate.InstallationChannelEnded"
        case .trollStoreUnavailable: return "AppUpdate.TrollStoreUnavailable"
        case .trollStoreNotStarted: return "AppUpdate.TrollStoreNotStarted"
        }
    }
}

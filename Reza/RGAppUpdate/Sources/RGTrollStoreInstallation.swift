// MARK: Regram — hand verified updates to TrollStore's documented installer.
import Foundation

public enum RGUpdateInstallationMethod: String, CaseIterable {
    case certificate
    case trollStore

    public var localizationKey: String {
        switch self {
        case .certificate: return "AppUpdate.MethodCertificate"
        case .trollStore: return "AppUpdate.MethodTrollStore"
        }
    }

    // TrollStore writes this marker in the installed application's bundle container.
    // Scheme availability alone cannot distinguish TrollStore from Apple's Magnifier.
    static func detected(bundleURL: URL, fileManager: FileManager = .default) -> Self {
        let marker = bundleURL.deletingLastPathComponent().appendingPathComponent("_TrollStore")
        return fileManager.fileExists(atPath: marker.path) ? .trollStore : .certificate
    }
}

enum RGTrollStoreInstallation {
    static func installationURL(packageURL: URL) throws -> URL {
        guard packageURL.scheme == "http", packageURL.host == "127.0.0.1",
              let port = packageURL.port, (1...65535).contains(port),
              packageURL.user == nil, packageURL.password == nil,
              packageURL.query == nil, packageURL.fragment == nil,
              packageURL.pathExtension == "ipa" else { throw RGUpdateError.invalidArchive }
        var components = URLComponents()
        components.scheme = "apple-magnifier"
        components.host = "install"
        components.queryItems = [URLQueryItem(name: "url", value: packageURL.absoluteString)]
        guard let url = components.url else { throw RGUpdateError.invalidArchive }
        return url
    }
}

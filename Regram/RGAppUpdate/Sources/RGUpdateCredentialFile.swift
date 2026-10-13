// MARK: Regram — bounded reads work even when a file provider omits file-size metadata.
import Foundation

public enum RGUpdateCredentialFileKind {
    case certificate
    case profiles
    case signingMaterials

    public func acceptsExtension(_ value: String) -> Bool {
        switch self {
        case .certificate: return ["p12", "pfx"].contains(value.lowercased())
        case .profiles: return value.lowercased() == "mobileprovision"
        case .signingMaterials: return RGUpdateCredentialFileKind.certificate.acceptsExtension(value) || RGUpdateCredentialFileKind.profiles.acceptsExtension(value)
        }
    }
}

public enum RGUpdateCredentialFileError: Error {
    case invalidType, tooLarge, empty, unreadable, certificateSelection
    public var localizationKey: String {
        switch self {
        case .invalidType: return "AppUpdate.ImportWrongType"
        case .tooLarge: return "AppUpdate.ImportTooLarge"
        case .empty: return "AppUpdate.ImportEmpty"
        case .unreadable: return "AppUpdate.ImportUnreadable"
        case .certificateSelection: return "AppUpdate.CertificateSelection"
        }
    }
}

public enum RGUpdateCredentialFile {
    public static let maximumBytes = 256 * 1024

    public static func read(url: URL, kind: RGUpdateCredentialFileKind) throws -> Data {
        guard url.isFileURL, kind.acceptsExtension(url.pathExtension) else { throw RGUpdateCredentialFileError.invalidType }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file: FileHandle
        do { file = try FileHandle(forReadingFrom: url) } catch { throw RGUpdateCredentialFileError.unreadable }
        defer { try? file.close() }
        let data: Data
        do { data = try file.read(upToCount: maximumBytes + 1) ?? Data() } catch { throw RGUpdateCredentialFileError.unreadable }
        guard !data.isEmpty else { throw RGUpdateCredentialFileError.empty }
        guard data.count <= maximumBytes else { throw RGUpdateCredentialFileError.tooLarge }
        return data
    }
}

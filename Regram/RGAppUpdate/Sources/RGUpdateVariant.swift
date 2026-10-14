// MARK: Regram — each installed identity selects its own asset from the shared release.
import Foundation

public enum RGUpdateVariant: String, CaseIterable, Codable, Sendable {
    case swiftgram = "Swiftgram"
    case nicegram = "Nicegram"
    case olai = "OLAI"
    case turrit = "Turrit"
    case nagram = "Nagram"

    public var bundleId: String {
        switch self {
        case .swiftgram: return "app.swiftgram.ios"
        case .nicegram: return "app.nicegram"
        case .olai: return "com.olcorporation.olai"
        case .turrit: return "com.seastar.turrit"
        case .nagram: return "xyz.nextalone.nagram"
        }
    }
    public var assetPrefix: String { self == .swiftgram ? "Regram" : "Regram-" + rawValue }
    public func assetName(version: String, build: Int64) -> String { "\(assetPrefix)-\(version)-b\(build).ipa" }

    public static func forBundleId(_ id: String?) -> RGUpdateVariant? {
        guard let id else { return nil }
        return allCases.first { id == $0.bundleId || id.hasPrefix($0.bundleId + ".") }
    }
    public static func forAssetName(_ name: String) -> RGUpdateVariant? {
        // Check named variants first; the legacy base asset keeps its original filename.
        if let variant = allCases.first(where: { $0 != .swiftgram && name.hasPrefix($0.assetPrefix + "-") }) { return variant }
        return name.hasPrefix("Regram-") ? .swiftgram : nil
    }
    public static var current: RGUpdateVariant {
        // Signing tools may change the bundle identifier. The packaging marker preserves identity.
        if let marker = Bundle.main.object(forInfoDictionaryKey: "RegramUpdateVariant") as? String, let value = Self(rawValue: marker) { return value }
        return forBundleId(Bundle.main.bundleIdentifier) ?? .swiftgram
    }
}

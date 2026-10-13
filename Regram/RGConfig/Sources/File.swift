import Foundation
import BuildConfig

public struct RGConfig: Codable {
    // Regram uses local settings unless a builder explicitly configures its own backend.
    public var apiUrl: String = ""
    public var webappUrl: String = ""
    public var botUsername: String = ""
    public var publicKey: String?
}

private func parseRGConfig(_ jsonString: String) -> RGConfig {
    let jsonData = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return (try? decoder.decode(RGConfig.self, from: jsonData)) ?? RGConfig()
}

private let baseAppBundleId = Bundle.main.bundleIdentifier!
private let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
public let RG_CONFIG: RGConfig = parseRGConfig(buildConfig.rgConfig)
public let RG_API_WEBAPP_URL_PARSED: URL? = URL(string: RG_CONFIG.webappUrl)

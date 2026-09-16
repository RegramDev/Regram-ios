import Foundation
import BuildConfig

public struct RGConfig: Codable {
    public var apiUrl: String = "https://api.swiftgram.app"
    public var webappUrl: String = "https://my.swiftgram.app"
    public var botUsername: String = "SwiftgramBot"
    public var publicKey: String?
    public var iaps: [String] = []
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
public let RG_API_WEBAPP_URL_PARSED = URL(string: RG_CONFIG.webappUrl)!
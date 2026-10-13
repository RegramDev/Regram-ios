// MARK: Regram — LCSign's public node list and manifest protocol.
import Foundation

public struct RGLCSignNode: Equatable, Identifiable {
    public let code: String
    public let name: String
    public let baseURL: URL
    public let priority: Int
    public var id: String { code }

    public static let fallback: [RGLCSignNode] = [
        .init(code: "gz", name: "GZ", baseURL: URL(string: "https://gz-i.lcsignx.com:8082")!, priority: 10),
        .init(code: "cf", name: "CF", baseURL: URL(string: "https://cf-i.lcsignx.com")!, priority: 20),
        .init(code: "jp", name: "JP", baseURL: URL(string: "https://jp-i.lcsignx.com")!, priority: 30),
        .init(code: "hk", name: "HK", baseURL: URL(string: "https://hk-i.lcsignx.com")!, priority: 40)
    ]

    public static func parse(_ data: Data) throws -> [RGLCSignNode] {
        struct Node: Decodable { let code: String; let name: String; let base_url: URL; let enabled: Bool; let priority: Int }
        struct Response: Decodable { let services: [Node] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.services.count <= 32 else { throw RGUpdateError.invalidManifest }
        var codes = Set<String>()
        return response.services.compactMap { node in
            guard node.enabled, trustedURL(node.base_url), node.base_url.path.isEmpty || node.base_url.path == "/", node.base_url.query == nil,
                  node.base_url.host == node.code + "-i.lcsignx.com", node.code.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }), codes.insert(node.code).inserted else { return nil }
            return RGLCSignNode(code: node.code, name: String(node.name.prefix(32)), baseURL: node.base_url, priority: node.priority)
        }.sorted { $0.priority < $1.priority }
    }

    public static func trustedURL(_ url: URL) -> Bool {
        guard RGUpdateRelease.validHTTPS(url), let host = url.host?.lowercased() else { return false }
        if host == "support.lcsignx.com" { return url.port == nil || url.port == 443 }
        let regex = try? NSRegularExpression(pattern: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?-i\.lcsignx\.com$"#)
        return regex?.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil && (url.port == nil || url.port == 443 || (host == "gz-i.lcsignx.com" && url.port == 8082))
    }

    public static func manifestRequest(packageURL: URL, bundleId: String, build: String) throws -> Data {
        // The node receives metadata only. The IPA is served exclusively on this device's loopback interface.
        guard packageURL.scheme == "http", packageURL.host == "127.0.0.1", packageURL.port != nil, packageURL.user == nil, packageURL.password == nil else { throw RGUpdateError.invalidManifest }
        return try JSONSerialization.data(withJSONObject: ["bundle_id": bundleId, "version": build, "title": "Regram", "ipa_url": packageURL.absoluteString])
    }

    public static func installationURL(manifest: URL) throws -> URL {
        guard trustedURL(manifest), manifest.path.hasPrefix("/ota/m/"), manifest.query == nil else { throw RGUpdateError.invalidManifest }
        var components = URLComponents()
        components.scheme = "itms-services"
        // Match LCSign's ManifestBuilder: an empty authority is required to
        // produce itms-services://? rather than the opaque itms-services:?.
        components.host = ""
        components.queryItems = [URLQueryItem(name: "action", value: "download-manifest"), URLQueryItem(name: "url", value: manifest.absoluteString)]
        guard let url = components.url else { throw RGUpdateError.invalidManifest }
        return url
    }

    public func manifestURL(token: String) throws -> URL {
        guard (6...128).contains(token.count), token.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw RGUpdateError.invalidManifest }
        return baseURL.appendingPathComponent("ota/m").appendingPathComponent(token)
    }

    public static func validateManifest(_ data: Data, bundleId: String, build: String, packageURL: URL) throws {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let items = plist["items"] as? [[String: Any]], items.count == 1,
              let metadata = items[0]["metadata"] as? [String: Any], metadata["bundle-identifier"] as? String == bundleId, metadata["bundle-version"] as? String == build, metadata["kind"] as? String == "software",
              let assets = items[0]["assets"] as? [[String: Any]], assets.count == 1, assets[0]["kind"] as? String == "software-package", assets[0]["url"] as? String == packageURL.absoluteString else { throw RGUpdateError.invalidManifest }
    }
}

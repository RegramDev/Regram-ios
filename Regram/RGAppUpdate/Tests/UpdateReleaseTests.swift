import Foundation

@main struct UpdateReleaseTests {
    static let hash = String(repeating: "a", count: 64)
    static func fixture(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var value: [String: Any] = ["tag_name": "v13.0-b34592", "draft": false, "prerelease": false, "body": "Update notes", "assets": [["name": "Regram-13.0-b34592.ipa", "size": 89000000, "digest": "sha256:" + hash, "browser_download_url": "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34592/Regram-13.0-b34592.ipa"]]]
        mutate(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }
    static func rejected(_ data: Data) {
        do { _ = try RGUpdateRelease.parseGitHub(data); fatalError("Invalid release accepted") } catch {}
    }
    static func main() throws {
        let release = try RGUpdateRelease.parseGitHub(fixture())
        assert(release.isNewer(version: "13.0", build: "34591"))
        assert(!release.isNewer(version: "13.0", build: "34592"))
        assert(!release.isNewer(version: "13.0", build: "34593"))
        assert(!release.isNewer(version: "14.0", build: "1"))
        assert(release.isNewer(version: "12.9", build: "99999"))
        assert(!release.isNewer(version: "unknown", build: "unknown"))
        rejected(try fixture { $0["draft"] = true })
        rejected(try fixture { $0["prerelease"] = true })
        rejected(try fixture { $0["tag_name"] = "v13.0-b99999" })
        rejected(try fixture { value in var assets = value["assets"] as! [[String: Any]]; assets.append(assets[0]); value["assets"] = assets })
        for mutation in ["digest": "sha256:wrong", "browser_download_url": "http://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34592/Regram-13.0-b34592.ipa"] {
            rejected(try fixture { value in var assets = value["assets"] as! [[String: Any]]; assets[0][mutation.key] = mutation.value; value["assets"] = assets })
        }
        rejected(try fixture { value in var assets = value["assets"] as! [[String: Any]]; assets[0].removeValue(forKey: "digest"); value["assets"] = assets })
        let node = RGLCSignNode.fallback[1]
        let manifest = try node.manifestURL(token: "aB1234")
        let url = try RGLCSignNode.installationURL(manifest: manifest)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        assert(url.scheme == "itms-services")
        assert(url.absoluteString.hasPrefix("itms-services://?action=download-manifest&"))
        assert(url.host?.isEmpty != false)
        assert(query.first { $0.name == "url" }?.value == manifest.absoluteString)
        for value in ["http://cf-i.lcsignx.com/ota/m/aB1234", "https://another.example.com/ota/m/aB1234", "https://cf-i.lcsignx.com/other/aB1234", "https://user:pass@cf-i.lcsignx.com/ota/m/aB1234", "https://cf-i.lcsignx.com:9443/ota/m/aB1234"] {
            do { _ = try RGLCSignNode.installationURL(manifest: URL(string: value)!); fatalError("Unsafe installation link accepted") } catch {}
        }
        do { _ = try node.manifestURL(token: "../other"); fatalError("Unsafe token accepted") } catch {}
        let packageURL = URL(string: "http://127.0.0.1:54321/token/Regram.ipa")!
        let body = try RGLCSignNode.manifestRequest(packageURL: packageURL, bundleId: "com.example.Regram", build: "34592")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: String]
        assert(json["ipa_url"] == packageURL.absoluteString)
        assert(Set(json.keys) == Set(["ipa_url", "bundle_id", "version", "title"]))
        let manifestBody: [String: Any] = ["items": [["assets": [["kind": "software-package", "url": packageURL.absoluteString]], "metadata": ["bundle-identifier": "com.example.Regram", "bundle-version": "34592", "kind": "software"]]]]
        let plist = try PropertyListSerialization.data(fromPropertyList: manifestBody, format: .xml, options: 0)
        try RGLCSignNode.validateManifest(plist, bundleId: "com.example.Regram", build: "34592", packageURL: packageURL)
        do { try RGLCSignNode.validateManifest(plist, bundleId: "com.other.app", build: "34592", packageURL: packageURL); fatalError("Wrong app manifest accepted") } catch {}
        do { try RGLCSignNode.validateManifest(plist, bundleId: "com.example.Regram", build: "1", packageURL: packageURL); fatalError("Wrong build manifest accepted") } catch {}
        print("Update release checks passed: identity, build ordering, checksum, channel and installation URL boundaries.")
    }
}

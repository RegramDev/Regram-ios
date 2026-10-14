import Foundation

@main enum UpdateVariantTests {
    static func fixture(_ variants: [RGUpdateVariant], duplicate: RGUpdateVariant? = nil) throws -> Data {
        var assets = variants.enumerated().map { index, variant -> [String: Any] in
            let name = variant.assetName(version: "13.0", build: 34607)
            return ["name": name, "size": 100 + index, "digest": "sha256:" + String(repeating: String(index + 1), count: 64), "browser_download_url": "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34607/" + name]
        }
        if let duplicate, let asset = assets.first(where: { ($0["name"] as? String) == duplicate.assetName(version: "13.0", build: 34607) }) { assets.append(asset) }
        return try JSONSerialization.data(withJSONObject: ["tag_name": "v13.0-b34607", "draft": false, "prerelease": false, "assets": assets])
    }
    static func main() throws {
        let data = try fixture(RGUpdateVariant.allCases)
        for (index, variant) in RGUpdateVariant.allCases.enumerated() {
            precondition(RGUpdateVariant.forBundleId(variant.bundleId) == variant)
            precondition(RGUpdateVariant.forBundleId(variant.bundleId + ".SIGNED") == variant)
            let release = try RGUpdateRelease.parseGitHub(data, variant: variant)
            precondition(release.variant == variant && release.downloadURL.lastPathComponent == variant.assetName(version: "13.0", build: 34607))
            precondition(release.sha256 == String(repeating: String(index + 1), count: 64) && release.size == Int64(100 + index))
            try release.validateCachedMetadata()
        }
        precondition(RGUpdateVariant.swiftgram.assetName(version: "13.0", build: 34607) == "Regram-13.0-b34607.ipa")
        precondition(RGUpdateVariant.forBundleId("app.nicegramfake") == nil)
        do { _ = try RGUpdateRelease.parseGitHub(fixture([.swiftgram]), variant: .nicegram); preconditionFailure("Another identity's package was selected") }
        catch RGUpdateError.incompatibleVariant {}
        do { _ = try RGUpdateRelease.parseGitHub(fixture(RGUpdateVariant.allCases, duplicate: .nicegram), variant: .nicegram); preconditionFailure("Duplicate matching assets were accepted") }
        catch RGUpdateError.invalidRelease {}
        _ = try RGUpdateRelease.parseGitHub(fixture(RGUpdateVariant.allCases, duplicate: .nicegram), variant: .swiftgram)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = RGUpdateCache(directory: directory)
        let release = try RGUpdateRelease.parseGitHub(data, variant: .nicegram)
        try cache.select(release)
        let own = try cache.load(installedVersion: "13.0", installedBuild: "34606", signer: nil, variant: .nicegram)
        precondition(own?.release == release)
        let other = try cache.load(installedVersion: "13.0", installedBuild: "34606", signer: nil, variant: .turrit)
        precondition(other == nil)
        precondition(!FileManager.default.fileExists(atPath: directory.path))
        print("Five update identities select only their own IPA and checksum; re-signing suffixes, legacy names, missing/duplicate assets and cache isolation passed.")
    }
}

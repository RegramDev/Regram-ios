import Foundation

@main struct TrollStoreInstallationTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = directory.appendingPathComponent("Regram.app")
        assert(RGUpdateInstallationMethod.detected(bundleURL: bundle) == .certificate)
        try Data().write(to: directory.appendingPathComponent("_TrollStore"))
        assert(RGUpdateInstallationMethod.detected(bundleURL: bundle) == .trollStore)
        let package = URL(string: "http://127.0.0.1:39123/random-route/Reza.ipa")!
        let installation = try RGTrollStoreInstallation.installationURL(packageURL: package)
        let components = URLComponents(url: installation, resolvingAgainstBaseURL: false)!
        assert(installation.absoluteString.hasPrefix("apple-magnifier://install?"))
        assert(components.queryItems == [URLQueryItem(name: "url", value: package.absoluteString)])
        for invalid in ["https://github.com/example/Reza.ipa", "http://192.168.1.1:123/Reza.ipa", "http://127.0.0.1/Reza.ipa", "http://name:password@127.0.0.1:123/Reza.ipa", "http://127.0.0.1:123/Reza.ipa?other=1", "http://127.0.0.1:123/Reza.zip"] {
            do { _ = try RGTrollStoreInstallation.installationURL(packageURL: URL(string: invalid)!); fatalError("Unexpected installer address accepted") }
            catch RGUpdateError.invalidArchive {}
        }
        assert(RGUpdateInstallationMethod(rawValue: "trollStore") == .trollStore)
        print("TrollStore checks passed: own installation marker, certificate fallback, exact scheme/query and local verified-package routes.")
    }
}

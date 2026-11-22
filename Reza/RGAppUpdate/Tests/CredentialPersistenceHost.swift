// Exercises the production Keychain and identity decoder in an isolated iOS app.
import Foundation
import UIKit
import Security

enum RGUpdateError: Error { case keychain }

@main final class CredentialPersistenceHost: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        let mode = CommandLine.arguments.last ?? ""
        let result: String
        do {
            let fixture = Data(repeating: 0x42, count: 8192)
            switch mode {
            case "store":
                try clear()
                try RGUpdateKeychain.write(JSONEncoder().encode(RGUpdateIdentity(p12: fixture, password: "synthetic-password", name: "Synthetic certificate")), account: "identity")
                try RGUpdateKeychain.write(JSONEncoder().encode([fixture]), account: "profiles")
                try verify()
            case "verify": try verify()
            case "legacy-store":
                try clear()
                struct Legacy: Encodable { let p12: Data; let password: String }
                try RGUpdateKeychain.write(JSONEncoder().encode(Legacy(p12: fixture, password: "synthetic-password")), account: "identity")
                try RGUpdateKeychain.write(Data("Synthetic certificate".utf8), account: "certificate-name")
            case "legacy-verify":
                guard let identity = RGUpdateIdentity.load(), identity.p12 == fixture, identity.password == "synthetic-password", identity.displayName == "Synthetic certificate" else { throw Failure.check }
            case "erase":
                try clear()
                guard RGUpdateIdentity.load() == nil, RGUpdateKeychain.read("profiles") == nil else { throw Failure.check }
            default: throw Failure.check
            }
            result = "PASSED: " + mode
        } catch {
            var query = RGUpdateKeychain.query("identity")
            query[kSecReturnAttributes as String] = true
            let status = SecItemCopyMatching(query as CFDictionary, nil)
            result = "FAILED: " + mode + ": " + String(describing: error) + ", status " + String(status)
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.txt")
        try? result.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private enum Failure: Error { case check }
    private func clear() throws {
        for key in ["identity", "certificate-name", "profiles"] { try RGUpdateKeychain.write(nil, account: key) }
    }
    private func verify() throws {
        let fixture = Data(repeating: 0x42, count: 8192)
        guard let identity = RGUpdateIdentity.load(), identity.p12 == fixture, identity.password == "synthetic-password", identity.displayName == "Synthetic certificate",
              let data = RGUpdateKeychain.read("profiles"), try JSONDecoder().decode([Data].self, from: data) == [fixture] else { throw Failure.check }
        var query = RGUpdateKeychain.query("identity")
        query[kSecReturnAttributes as String] = true
        var attributes: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &attributes) == errSecSuccess,
              let values = attributes as? [String: Any],
              values[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String else { throw Failure.check }
    }
}

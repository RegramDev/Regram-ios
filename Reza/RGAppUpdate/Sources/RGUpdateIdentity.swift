// MARK: Regram — one durable Keychain record for the certificate, password and name.
import Foundation

struct RGUpdateIdentity: Codable {
    let p12: Data
    let password: String
    // Optional so certificates imported by b34593 remain readable.
    let name: String?

    static func load() -> RGUpdateIdentity? {
        guard let data = RGUpdateKeychain.read("identity"),
              let identity = try? JSONDecoder().decode(RGUpdateIdentity.self, from: data),
              !identity.p12.isEmpty else { return nil }
        return identity
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return String(data: RGUpdateKeychain.read("certificate-name") ?? Data(), encoding: .utf8) ?? ""
    }
}

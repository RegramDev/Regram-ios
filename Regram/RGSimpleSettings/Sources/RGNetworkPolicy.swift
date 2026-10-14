// MARK: Regram — transport preferences shared with the notification extension.
import Foundation
public struct RGNetworkPolicy: Equatable {
    public enum IPVersion: Int, CaseIterable { case automatic = 0, ipv4 = 4, ipv6 = 6 }
    public static let didChange = Notification.Name("Regram.NetworkPolicy.DidChange")
    public var dohEnabled: Bool
    public var endpoint: String
    public var ipVersion: IPVersion
    public init(dohEnabled: Bool = false, endpoint: String = "", ipVersion: IPVersion = .automatic) { self.dohEnabled = dohEnabled; self.endpoint = endpoint; self.ipVersion = ipVersion }
    public static func validEndpoint(_ value: String) -> Bool {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil, components.fragment == nil, components.url != nil else { return false }
        return value.utf8.count <= 2048
    }
    public var effectiveEndpoint: String? { dohEnabled ? (Self.validEndpoint(endpoint) ? endpoint.trimmingCharacters(in: .whitespacesAndNewlines) : "invalid-doh-endpoint") : nil }
    public init(defaults: UserDefaults) {
        self.init(dohEnabled: defaults.bool(forKey: "customDoHEnabled"), endpoint: defaults.string(forKey: "customDoHEndpoint") ?? "", ipVersion: IPVersion(rawValue: defaults.integer(forKey: "ipVersionPolicy")) ?? .automatic)
    }
    public func save(to defaults: UserDefaults) {
        defaults.set(dohEnabled, forKey: "customDoHEnabled"); defaults.set(endpoint, forKey: "customDoHEndpoint"); defaults.set(ipVersion.rawValue, forKey: "ipVersionPolicy")
    }
}
public extension RGSimpleSettings {
    var networkPolicy: RGNetworkPolicy {
        get { RGNetworkPolicy(defaults: Bundle.main.bundlePath.hasSuffix(".appex") ? APP_GROUP_USER_DEFAULTS ?? UserDefaults.standard : UserDefaults.standard) }
        set { newValue.save(to: UserDefaults.standard); if let shared = APP_GROUP_USER_DEFAULTS { newValue.save(to: shared) }; NotificationCenter.default.post(name: RGNetworkPolicy.didChange, object: nil) }
    }
}

// MARK: Regram — transport preferences shared with the notification extension.
import Foundation
public struct RGNetworkPolicy: Equatable {
    public enum IPVersion: Int, CaseIterable {
        case automatic = 0, ipv4Only = 1, ipv4 = 4, ipv6 = 6, ipv6Only = 2
        public var titleKey: String {
            switch self {
            case .automatic: return "NetworkPolicy.Automatic"
            case .ipv4Only: return "NetworkPolicy.IPv4Only"
            case .ipv4: return "NetworkPolicy.IPv4"
            case .ipv6: return "NetworkPolicy.IPv6"
            case .ipv6Only: return "NetworkPolicy.IPv6Only"
            }
        }
    }
    public enum DNSMode: String, CaseIterable {
        case automatic, system, custom
        public var titleKey: String {
            switch self {
            case .automatic: return "NetworkPolicy.BuiltInDNS"
            case .system: return "DNSDiagnostics.SystemDNS"
            case .custom: return "NetworkPolicy.DoH"
            }
        }
    }
    public var dnsMode: DNSMode {
        get { dohEnabled ? .custom : useSystemDNS ? .system : .automatic }
        set { dohEnabled = newValue == .custom; useSystemDNS = newValue == .system }
    }
    public static let didChange = Notification.Name("Regram.NetworkPolicy.DidChange")
    public var dohEnabled: Bool
    public var useSystemDNS: Bool
    public var disableBackupAddresses: Bool
    public var endpoint: String
    public var ipVersion: IPVersion
    public init(dohEnabled: Bool = false, endpoint: String = "", ipVersion: IPVersion = .automatic, useSystemDNS: Bool = false, disableBackupAddresses: Bool = false) { self.dohEnabled = dohEnabled; self.endpoint = endpoint; self.ipVersion = ipVersion; self.useSystemDNS = useSystemDNS && !dohEnabled; self.disableBackupAddresses = disableBackupAddresses }
    public static func validEndpoint(_ value: String) -> Bool {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil, components.fragment == nil, components.query == nil, components.port.map({ (1...65535).contains($0) }) ?? true, components.url != nil else { return false }
        return value.utf8.count <= 2048 && value.trimmingCharacters(in: .whitespacesAndNewlines).rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
    public var effectiveEndpoint: String? { dohEnabled ? (Self.validEndpoint(endpoint) ? endpoint.trimmingCharacters(in: .whitespacesAndNewlines) : "invalid-doh-endpoint") : nil }
    public init(defaults: UserDefaults) {
        self.init(dohEnabled: defaults.bool(forKey: "customDoHEnabled"), endpoint: defaults.string(forKey: "customDoHEndpoint") ?? "", ipVersion: IPVersion(rawValue: defaults.integer(forKey: "ipVersionPolicy")) ?? .automatic, useSystemDNS: defaults.bool(forKey: "localDNSForProxyHost"), disableBackupAddresses: defaults.bool(forKey: "disableBackupAddresses"))
    }
    public func save(to defaults: UserDefaults) {
        defaults.set(dohEnabled, forKey: "customDoHEnabled"); defaults.set(endpoint, forKey: "customDoHEndpoint"); defaults.set(ipVersion.rawValue, forKey: "ipVersionPolicy"); defaults.set(useSystemDNS && !dohEnabled, forKey: "localDNSForProxyHost"); defaults.set(disableBackupAddresses, forKey: "disableBackupAddresses")
    }
}
public extension RGSimpleSettings {
    var networkPolicy: RGNetworkPolicy {
        get { RGNetworkPolicy(defaults: Bundle.main.bundlePath.hasSuffix(".appex") ? APP_GROUP_USER_DEFAULTS ?? UserDefaults.standard : UserDefaults.standard) }
        set { if newValue.dohEnabled { UserDefaults.standard.set(false, forKey: "localDNSForProxyHost"); APP_GROUP_USER_DEFAULTS?.set(false, forKey: "localDNSForProxyHost") }; newValue.save(to: UserDefaults.standard); if let shared = APP_GROUP_USER_DEFAULTS { newValue.save(to: shared) }; NotificationCenter.default.post(name: RGNetworkPolicy.didChange, object: nil) }
    }
}

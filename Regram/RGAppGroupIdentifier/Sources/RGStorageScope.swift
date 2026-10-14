// MARK: Regram — signing tools may lend the same App Group to several installed identities.
import Foundation

public enum RGStorageScope {
    public static let directoryName = "regram-identities"
    public static let preferencesPrefix = "Regram.Identity."
    private static let identities = ["Swiftgram": "app.swiftgram.ios", "Nicegram": "app.nicegram", "OLAI": "com.olcorporation.olai", "Turrit": "com.seastar.turrit", "Nagram": "xyz.nextalone.nagram"]

    public static func identity(marker: String?, bundleId: String?) -> String {
        if let marker, let id = identities[marker] { return id }
        if let bundleId, let id = identities.values.first(where: { bundleId == $0 || bundleId.hasPrefix($0 + ".") }) { return id }
        return "app.swiftgram.ios"
    }
    public static var current: String {
        identity(marker: Bundle.main.object(forInfoDictionaryKey: "RegramUpdateVariant") as? String, bundleId: Bundle.main.bundleIdentifier)
    }
    public static var keychainScope: String? { current == "app.swiftgram.ios" ? nil : current }
    public static func keychainService(_ name: String) -> String {
        keychainScope.map { "org.telegram.scoped." + $0 + "/" + name } ?? name
    }
    public static func preferencePrefix(identity: String) -> String {
        identity == "app.swiftgram.ios" ? "" : preferencesPrefix + identity + "."
    }
    public static func dataURL(container: URL, identity: String) -> URL {
        identity == "app.swiftgram.ios" ? container : container.appendingPathComponent(directoryName, isDirectory: true).appendingPathComponent(identity, isDirectory: true)
    }
}

/// Preserve the existing shared suite, but give each additional identity its own key namespace.
public final class RGScopedSharedDefaults: UserDefaults, @unchecked Sendable {
    private let backing: UserDefaults
    private let prefix: String
    public init(backing: UserDefaults, prefix: String) {
        self.backing = backing; self.prefix = prefix
        super.init(suiteName: nil)!
    }
    override public func object(forKey key: String) -> Any? { backing.object(forKey: prefix + key) }
    override public func set(_ value: Any?, forKey key: String) { backing.set(value, forKey: prefix + key) }
    override public func removeObject(forKey key: String) { backing.removeObject(forKey: prefix + key) }
    override public func string(forKey key: String) -> String? { backing.string(forKey: prefix + key) }
    override public func array(forKey key: String) -> [Any]? { backing.array(forKey: prefix + key) }
    override public func dictionary(forKey key: String) -> [String: Any]? { backing.dictionary(forKey: prefix + key) }
    override public func data(forKey key: String) -> Data? { backing.data(forKey: prefix + key) }
    override public func stringArray(forKey key: String) -> [String]? { backing.stringArray(forKey: prefix + key) }
    override public func integer(forKey key: String) -> Int { backing.integer(forKey: prefix + key) }
    override public func float(forKey key: String) -> Float { backing.float(forKey: prefix + key) }
    override public func double(forKey key: String) -> Double { backing.double(forKey: prefix + key) }
    override public func bool(forKey key: String) -> Bool { backing.bool(forKey: prefix + key) }
    override public func url(forKey key: String) -> URL? { backing.url(forKey: prefix + key) }
    override public func set(_ value: Int, forKey key: String) { backing.set(value, forKey: prefix + key) }
    override public func set(_ value: Float, forKey key: String) { backing.set(value, forKey: prefix + key) }
    override public func set(_ value: Double, forKey key: String) { backing.set(value, forKey: prefix + key) }
    override public func set(_ value: Bool, forKey key: String) { backing.set(value, forKey: prefix + key) }
    override public func set(_ value: URL?, forKey key: String) { backing.set(value, forKey: prefix + key) }
    override public func register(defaults: [String: Any]) { backing.register(defaults: Dictionary(uniqueKeysWithValues: defaults.map { (prefix + $0.key, $0.value) })) }
    override public func dictionaryRepresentation() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: backing.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }.map { (String($0.key.dropFirst(prefix.count)), $0.value) })
    }
    override public func synchronize() -> Bool { backing.synchronize() }
}

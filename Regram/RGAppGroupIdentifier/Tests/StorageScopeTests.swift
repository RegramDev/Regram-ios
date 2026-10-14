import Foundation

@main enum StorageScopeTests {
    static func main() {
        let suite = "Regram.StorageScope.Tests." + UUID().uuidString
        let backing = UserDefaults(suiteName: suite)!
        defer { backing.removePersistentDomain(forName: suite) }
        let root = URL(fileURLWithPath: "/synthetic-shared-container")
        let identities = ["Swiftgram": "app.swiftgram.ios", "Nicegram": "app.nicegram", "OLAI": "com.olcorporation.olai", "Turrit": "com.seastar.turrit", "Nagram": "xyz.nextalone.nagram"]
        var paths = Set<String>()
        for (marker, expected) in identities {
            let identity = RGStorageScope.identity(marker: marker, bundleId: "renamed.installation")
            precondition(identity == expected)
            precondition(RGStorageScope.identity(marker: nil, bundleId: expected + ".NotificationService") == expected)
            paths.insert(RGStorageScope.dataURL(container: root, identity: identity).path)
            let prefix = RGStorageScope.preferencePrefix(identity: identity)
            let defaults: UserDefaults = prefix.isEmpty ? backing : RGScopedSharedDefaults(backing: backing, prefix: prefix)
            defaults.set(marker, forKey: "account"); defaults.set(true, forKey: "enabled"); defaults.set(17, forKey: "count")
            defaults.register(defaults: ["registered": "value"])
            precondition(defaults.string(forKey: "account") == marker && defaults.bool(forKey: "enabled") && defaults.integer(forKey: "count") == 17)
            precondition(defaults.string(forKey: "registered") == "value")
        }
        precondition(paths.count == 5)
        precondition(RGStorageScope.dataURL(container: root, identity: "app.swiftgram.ios") == root)
        let na = RGScopedSharedDefaults(backing: backing, prefix: RGStorageScope.preferencePrefix(identity: "xyz.nextalone.nagram"))
        let ng = RGScopedSharedDefaults(backing: backing, prefix: RGStorageScope.preferencePrefix(identity: "app.nicegram"))
        precondition(na.string(forKey: "account") == "Nagram" && ng.string(forKey: "account") == "Nicegram")
        na.removeObject(forKey: "account")
        precondition(backing.string(forKey: "account") == "Swiftgram" && ng.string(forKey: "account") == "Nicegram")
        precondition(na.dictionaryRepresentation()["Regram.Identity.app.nicegram.account"] == nil)
        print("Five identities are isolated under a pooled signing group; extensions agree, typed preferences are scoped, and the legacy data path is preserved.")
    }
}

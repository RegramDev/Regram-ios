import Foundation

@main enum NamingMigrationTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        let suite = "app.regram.naming-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "sg_db_reset")
        rgMigratedPreferenceKey("rg_db_reset", legacyKey: "sg_db_reset", defaults: defaults)
        expect(defaults.bool(forKey: "rg_db_reset"), "An armed reset must survive the upgrade")
        expect(defaults.object(forKey: "sg_db_reset") == nil, "Legacy preference must be consumed")
        defaults.set(false, forKey: "rg_full_wipe")
        defaults.set(true, forKey: "sg_full_wipe")
        rgMigratedPreferenceKey("rg_full_wipe", legacyKey: "sg_full_wipe", defaults: defaults)
        expect(!defaults.bool(forKey: "rg_full_wipe"), "An explicit current value must win, including false")
        defaults.set(true, forKey: "sg_migrated_sgui_settings_v1")
        rgMigratedPreferenceKey("rg_migrated_rgui_settings_v1", legacyKey: "sg_migrated_sgui_settings_v1", defaults: defaults)
        expect(defaults.bool(forKey: "rg_migrated_rgui_settings_v1"), "Completed migrations must not be repeated")
        rgMigratedPreferenceKey("rg_db_reset", legacyKey: "sg_db_reset", defaults: defaults)
        expect(defaults.bool(forKey: "rg_db_reset"), "Migration must be idempotent")
        rgMigratedPreferenceKey("rg_absent", legacyKey: "sg_absent", defaults: defaults)
        expect(defaults.object(forKey: "rg_absent") == nil, "Missing preferences must remain absent")

        for suffix in RGAppIconNames.renamedSuffixes {
            expect(RGAppIconNames.canonicalName("SG" + suffix) == "RG" + suffix, "Legacy icon must keep its picker selection")
        }
        expect(RGAppIconNames.canonicalName(nil) == nil, "The primary icon remains nil")
        for name in ["RGAnime", "RGSilver", "BlueIcon", "SGUnknown"] {
            expect(RGAppIconNames.canonicalName(name) == name, "Unrelated icon names must be preserved")
        }

        let decoder = JSONDecoder()
        var web = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RGWebSettings.defaultValue)) as! [String: Any]
        var global = web["global"] as! [String: Any]
        global["canEditSettings"] = true
        web["global"] = global
        var user = web["user"] as! [String: Any]
        user["contentReasons"] = ["c2F2ZWQ="]
        user["canBuyInBeta"] = false
        web["user"] = user
        let legacy: [String: Any] = ["sg": web, "sggh": ["announcementsData": "saved announcement"], "storedHash": 42]
        let migrated = try decoder.decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(migrated.rgWebSettings.global.canEditSettings, "Saved web settings must not be replaced with defaults")
        expect(!migrated.rgWebSettings.user.canBuyInBeta, "Saved false values must survive")
        expect(migrated.rgWebSettings.user.expandedContentReasons() == ["saved"], "Saved content rules must survive")
        expect(migrated.rgGHSettings.announcementsData == "saved announcement", "Legacy announcements must survive")
        expect(migrated.hash == 42, "Upstream configuration fields must survive")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as! [String: Any]
        expect(encoded["rg"] != nil && encoded["rggh"] != nil, "New records must use current keys")
        expect(encoded["sg"] == nil && encoded["sggh"] == nil, "New records must not write legacy keys")
        let roundTrip = try decoder.decode(AppConfiguration.self, from: JSONEncoder().encode(migrated))
        expect(roundTrip == migrated, "Migrated records must round-trip")

        var mixed = legacy
        mixed["rggh"] = ["announcementsData": "current announcement"]
        let current = try decoder.decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: mixed))
        expect(current.rgGHSettings.announcementsData == "current announcement", "Current storage keys must take precedence")
        let empty = try decoder.decode(AppConfiguration.self, from: Data("{}".utf8))
        expect(empty == .defaultValue, "Missing configuration must retain application defaults")
        print("Naming migrations passed: preference state, icon selection and persisted app configuration")
    }
}

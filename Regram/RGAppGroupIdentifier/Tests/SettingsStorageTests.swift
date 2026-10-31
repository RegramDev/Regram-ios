import Foundation

@main enum SettingsStorageTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        expect(RGAppIconNames.canonicalName(nil) == nil, "The primary icon remains nil")
        expect(RGAppIconNames.canonicalName("RGAnime") == nil, "Retired RG artwork selects the current primary")
        expect(RGAppIconNames.canonicalName("RGSilver") == "RGSilver", "The existing beta alternate-icon identifier remains available")
        for name in ["BlueIcon", "SGSilver", "SGAnime"] {
            expect(RGAppIconNames.canonicalName(name) == nil, "Removed artwork must resolve to primary instead of retaining a missing asset")
        }

        expect(RGAppIconNames.canonicalName("RGGathering") == "RGGathering", "The approved alternate must survive normalization")

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
        let retired = try decoder.decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(retired.rgWebSettings == .defaultValue && retired.rgGHSettings == .defaultValue, "Swiftgram settings must be ignored")
        expect(retired.hash == 42, "Upstream configuration fields must survive")
        let currentData: [String: Any] = ["rg": web, "rggh": ["announcementsData": "current announcement"], "storedHash": 42]
        let current = try decoder.decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: currentData))
        expect(current.rgWebSettings.global.canEditSettings && !current.rgWebSettings.user.canBuyInBeta, "Current RG settings must survive")
        expect(current.rgWebSettings.user.expandedContentReasons() == ["saved"], "Current RG content rules must survive")
        expect(current.rgGHSettings.announcementsData == "current announcement", "Current RG announcements must survive")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as! [String: Any]
        expect(encoded["rg"] != nil && encoded["rggh"] != nil && encoded["sg"] == nil && encoded["sggh"] == nil, "Only RG settings keys are written")
        let roundTrip = try decoder.decode(AppConfiguration.self, from: JSONEncoder().encode(current))
        expect(roundTrip == current, "Current RG settings must round-trip")
        let empty = try decoder.decode(AppConfiguration.self, from: Data("{}".utf8))
        expect(empty == .defaultValue, "Missing configuration must retain application defaults")
        print("RG storage passed: current configuration preservation and Swiftgram configuration/icon rejection")
    }
}

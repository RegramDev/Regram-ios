// MARK: Regram — excluded from settings backup and iCloud keychain.
import Foundation
import Security

enum RGUpdateKeychain {
    static func query(_ account: String) -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Regram") + ".app-update", kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    static func read(_ account: String) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data?, account: String) throws {
        let query = query(account)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw RGUpdateError.keychain }
            return
        }
        // Survives process restarts and updates, and remains readable by automatic
        // preparation after the first unlock. It never syncs to other devices.
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(values, uniquingKeysWith: { _, new in new }) as CFDictionary, nil) }
        guard status == errSecSuccess else { throw RGUpdateError.keychain }
    }
}

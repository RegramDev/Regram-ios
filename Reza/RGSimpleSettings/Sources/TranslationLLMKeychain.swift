// MARK: Regram — credentials stay local and are excluded from settings backups.
import Foundation
import Security

public extension RGSimpleSettings {
    var translationLLMAPIKey: String {
        var query = Self.translationLLMKeychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    func setTranslationLLMAPIKey(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = Self.translationLLMKeychainQuery
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(update, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    private static var translationLLMKeychainQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Regram") + ".translation.llm",
            kSecAttrAccount as String: "api-key",
            kSecAttrSynchronizable as String: false
        ]
    }
}

import Foundation

// MARK: Regram
/// Move a preference to its current name without replacing an explicitly saved value.
@discardableResult
public func rgMigratedPreferenceKey(_ key: String, legacyKey: String, defaults: UserDefaults = .standard) -> String {
    if defaults.object(forKey: key) == nil, let value = defaults.object(forKey: legacyKey) {
        defaults.set(value, forKey: key)
    }
    defaults.removeObject(forKey: legacyKey)
    return key
}

// MARK: Regram — a shared, opt-in notification experiment; unrelated features stay unchanged.
import Foundation

public enum RGNotificationExperiment {
    public static let key = "notificationRecoveryExperiment"
    public static let changed = Notification.Name("RGNotificationRecoveryExperimentChanged")

    public static var isEnabled: Bool {
        guard let defaults = rgSharedUserDefaults() else { return false }
        // Extensions can handle several requests in the same process. Refresh once per snapshot.
        defaults.synchronize()
        if let value = defaults.object(forKey: key) as? Bool { return value }
        return defaults.bool(forKey: "legacyNotificationsFix")
    }

    public static func setEnabled(_ enabled: Bool) {
        guard let defaults = rgSharedUserDefaults() else { return }
        defaults.set(enabled, forKey: key)
        defaults.removeObject(forKey: "legacyNotificationsFix")
        defaults.synchronize()
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

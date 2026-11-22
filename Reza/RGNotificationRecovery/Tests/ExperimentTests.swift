import Foundation

private let suite = "app.regram.notification-tests." + UUID().uuidString
func rgSharedUserDefaults() -> UserDefaults? { UserDefaults(suiteName: suite) }

@main enum ExperimentTests {
    static func main() {
        let defaults = rgSharedUserDefaults()!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(!RGNotificationExperiment.isEnabled)
        defaults.set(true, forKey: "legacyNotificationsFix")
        precondition(RGNotificationExperiment.isEnabled)
        var changes = 0
        let observer = NotificationCenter.default.addObserver(forName: RGNotificationExperiment.changed, object: nil, queue: nil) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        RGNotificationExperiment.setEnabled(false)
        precondition(!RGNotificationExperiment.isEnabled && defaults.object(forKey: "legacyNotificationsFix") == nil)
        RGNotificationExperiment.setEnabled(true)
        precondition(RGNotificationExperiment.isEnabled && changes == 2)
        let requestSnapshot = RGNotificationExperiment.isEnabled
        RGNotificationExperiment.setEnabled(false)
        precondition(requestSnapshot && !RGNotificationExperiment.isEnabled)
        print("Notification experiment passed: default off, old preference migration, explicit disable, change signals and immutable request snapshot.")
    }
}

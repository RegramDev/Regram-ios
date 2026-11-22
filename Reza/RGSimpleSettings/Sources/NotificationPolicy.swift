// MARK: Regram — shared by the notification extension and bounded startup checks.
import Foundation

public enum RGNotificationPolicy {
    public static let maximumStartupAttempts = 3
    // Finish before the system's approximately 30-second extension deadline.
    public static let processingDeadline: Double = 24
    public static func isPlausibleEncryptedPayload(byteCount: Int) -> Bool {
        return byteCount >= 40 && (byteCount - 24) % 16 == 0
    }
    public static func retryDelay(attempt: Int) -> Double { return 0.2 * Double(attempt) }
    public static func shouldSuppress(markedControl: Bool, hasText: Bool, hasAttachments: Bool, hasSender: Bool) -> Bool {
        return markedControl || (!hasText && !hasAttachments && !hasSender)
    }
    public static func shouldRecoverBadge(foreignSession: Bool, markedControl: Bool) -> Bool {
        return !foreignSession && !markedControl
    }
}

// MARK: Regram — signed declarations are not proof of notification-filtering authorization.
import Foundation
import UserNotifications

public enum RGNotificationRecovery {
    public static let emptyThread = "empty-notification"
    public static let resolvedKey = "rg_notification_resolved_v1"
    public static let quietKey = "rg_notification_quiet_v1"
    public static let filteringEntitlement = "com.apple.developer.usernotifications.filtering"

    public static func shouldUseLockedPreview(fileSaysLocked: Bool, hasConfiguredPasscode: Bool?) -> Bool {
        // Unknown/unavailable credentials retain privacy; only authoritative removal overrides a file.
        fileSaysLocked && hasConfiguredPasscode != false
    }

    public static func isGenericMessage(_ value: String) -> Bool {
        let normalized = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        return normalized == "you have a new message" || normalized == "you have a new message."
    }

    public static func isPlaceholder(title: String, body: String, userInfo: [AnyHashable: Any], hasAttachments: Bool) -> Bool {
        // A real message, including an intentional locked-app privacy preview, can use this text.
        guard userInfo[resolvedKey] as? Bool != true, !hasAttachments, userInfo["peerId"] == nil else { return false }
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let localizedEncrypted = ["PUSH_ENCRYPTED_MESSAGE", "ENCRYPTED_MESSAGE"].contains(alert?["loc-key"] as? String ?? "")
        let rawBody = (aps?["alert"] as? String) ?? (alert?["body"] as? String) ?? ""
        // Require raw payload evidence; a generic app title alone may be a legitimate private preview.
        guard localizedEncrypted || userInfo["p"] is String || isGenericMessage(rawBody) else { return false }
        return localizedEncrypted || isGenericMessage(body) || (body.isEmpty && isGenericMessage(rawBody))
    }

    public static func shouldRemove(_ content: UNNotificationContent) -> Bool {
        content.threadIdentifier == emptyThread || content.userInfo[quietKey] as? Bool == true || isPlaceholder(title: content.title, body: content.body, userInfo: content.userInfo, hasAttachments: !content.attachments.isEmpty)
    }

    public static func quietContent(badge: NSNumber?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        // Whitespace-only alert fields may be rejected as empty and restore the original APNs alert.
        content.title = "Regram"
        content.threadIdentifier = emptyThread
        content.userInfo = [quietKey: true]
        content.badge = badge
        content.sound = nil
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
            content.relevanceScore = 0
        }
        return content
    }

    /// A conservative eligibility check, not an API for reading the kernel's authorization state.
    /// Re-signed certificates need the capability in the extension's matching, unexpired profile.
    public static func canUseFiltering(signatureDeclared: Bool, profile: Data?, bundleIdentifier: String, now: Date = Date()) -> Bool {
        guard signatureDeclared else { return false }
        // Store-installed and permanently signed apps may not carry a profile. Keep their declared
        // filtering path; cleanup remains independent because this is not kernel authorization.
        guard let profile else { return true }
        guard profile.count <= 16 * 1024 * 1024,
              let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let value = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound], options: [], format: nil),
              let dictionary = value as? [String: Any],
              let expiration = dictionary["ExpirationDate"] as? Date, expiration > now,
              let entitlements = dictionary["Entitlements"] as? [String: Any],
              entitlements[filteringEntitlement] as? Bool == true,
              let identifier = entitlements["application-identifier"] as? String,
              let team = (dictionary["ApplicationIdentifierPrefix"] as? [String])?.first,
              identifier.hasPrefix(team + ".") else { return false }
        let pattern = String(identifier.dropFirst(team.count + 1))
        if pattern == bundleIdentifier { return true }
        guard pattern.hasSuffix("*"), pattern.filter({ $0 == "*" }).count == 1 else { return false }
        return bundleIdentifier.hasPrefix(String(pattern.dropLast()))
    }

    public static func filteringEligible(signatureDeclared: Bool, bundle: Bundle = .main) -> Bool {
        let profile = try? Data(contentsOf: bundle.bundleURL.appendingPathComponent("embedded.mobileprovision"))
        return canUseFiltering(signatureDeclared: signatureDeclared, profile: profile, bundleIdentifier: bundle.bundleIdentifier ?? "")
    }

    public static func removeDeliveredPlaceholders(center: UNUserNotificationCenter = .current()) {
        center.getDeliveredNotifications { notifications in
            let ids = notifications.filter { shouldRemove($0.request.content) }.map { $0.request.identifier }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }
}

// MARK: Regram — a request-wide admission budget, before network buffers or cached files are read.
public final class RGNotificationResourceBudget {
    public static let maximumResourceBytes: Int64 = 2 * 1024 * 1024
    public static let maximumTotalBytes: Int64 = 6 * 1024 * 1024
    private let lock = NSLock()
    private var remaining = maximumTotalBytes

    public init() {}

    public func reserve(size: Int64?) -> Bool {
        let amount = size ?? Self.maximumResourceBytes
        guard amount > 0, amount <= Self.maximumResourceBytes else { return false }
        self.lock.lock()
        defer { self.lock.unlock() }
        guard amount <= self.remaining else { return false }
        self.remaining -= amount
        return true
    }

    public static func permitsChunk(offset: Int64, count: Int, lowerBound: Int, upperBound: Int, maximumBytes: Int64) -> Bool {
        guard offset >= 0, count >= 0, lowerBound >= 0, upperBound >= lowerBound, upperBound <= count,
              maximumBytes > 0, maximumBytes <= maximumResourceBytes, offset <= maximumBytes else { return false }
        return Int64(count) <= maximumBytes - offset
    }

    public static func cachedData(path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Int(maximumResourceBytes) + 1), data.count <= maximumResourceBytes else { return nil }
        return data
    }

    public static func cachedFileIsWithinBudget(path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value > 0 && size.int64Value <= maximumResourceBytes
    }
}

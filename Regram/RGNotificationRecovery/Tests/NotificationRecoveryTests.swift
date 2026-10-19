import Foundation
import UserNotifications

private func expect(_ value: @autoclosure () -> Bool, _ description: String) {
    if !value() { fatalError(description) }
}
private func profile(allowed: Bool, identifier: String = "TEAM.app.example.NotificationService", expiration: Date = Date(timeIntervalSince1970: 4_000_000_000)) -> Data {
    let values: [String: Any] = ["ApplicationIdentifierPrefix": ["TEAM"], "ExpirationDate": expiration,
        "Entitlements": ["application-identifier": identifier, RGNotificationRecovery.filteringEntitlement: allowed]]
    return Data([0x30, 0x82, 0, 1]) + (try! PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)) + Data([0, 1])
}
@main enum Tests {
    static func main() {
        expect(!RGNotificationRecovery.shouldUseLockedPreview(fileSaysLocked: true, hasConfiguredPasscode: false), "An authoritatively removed passcode overrides a stale locked file")
        expect(RGNotificationRecovery.shouldUseLockedPreview(fileSaysLocked: true, hasConfiguredPasscode: true), "Keep real password-lock privacy")
        expect(RGNotificationRecovery.shouldUseLockedPreview(fileSaysLocked: true, hasConfiguredPasscode: nil), "Unavailable/legacy credentials must not expose message text")
        expect(!RGNotificationRecovery.shouldUseLockedPreview(fileSaysLocked: false, hasConfiguredPasscode: true), "An unlocked app keeps ordinary previews")
        let id = "app.example.NotificationService"
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func eligible(_ declared: Bool, _ data: Data?) -> Bool {
            RGNotificationRecovery.canUseFiltering(signatureDeclared: declared, profile: data, bundleIdentifier: id, now: now)
        }
        expect(eligible(true, profile(allowed: true)), "Keep filtering for matching approved profiles")
        expect(!eligible(true, profile(allowed: false)), "A copied true declaration does not grant a restricted entitlement")
        expect(!eligible(false, profile(allowed: true)), "Both signature and profile are required")
        expect(eligible(true, nil), "Profile-less installations retain the declared filtering path")
        expect(!eligible(true, profile(allowed: true, identifier: "TEAM.other.app")), "Reject another application's profile")
        expect(!eligible(true, profile(allowed: true, expiration: now)), "Reject expired profiles")
        expect(eligible(true, profile(allowed: true, identifier: "TEAM.app.example.*")), "Support matching wildcard profiles")
        expect(!eligible(true, profile(allowed: true, identifier: "TEAM.app.*.NotificationService")), "Reject an interior wildcard")
        expect(!eligible(true, Data("not a profile".utf8)), "Malformed profiles must not enable filtering")
        expect(!eligible(true, Data(repeating: 0, count: 17 * 1024 * 1024)), "Bound profile decoding")

        func content(_ body: String, title: String = "", info: [AnyHashable: Any] = [:]) -> UNMutableNotificationContent {
            let result = UNMutableNotificationContent(); result.title = title; result.body = body; result.userInfo = info; return result
        }
        for text in ["You have a new message", " YOU HAVE A NEW MESSAGE. \n", "You\u{a0}have a new message"] {
            expect(RGNotificationRecovery.shouldRemove(content(text, title: "Regram", info: ["p": "synthetic"])), "Recognize unmarked original encrypted fallbacks")
        }
        expect(RGNotificationRecovery.shouldRemove(content("", info: ["aps": ["alert": ["loc-key": "PUSH_ENCRYPTED_MESSAGE"]]])), "Recognize the server's localization key")
        expect(RGNotificationRecovery.shouldRemove(content("", info: ["aps": ["alert": ["loc-key": "ENCRYPTED_MESSAGE"]]])), "Recognize the alternate encrypted-message localization template")
        expect(RGNotificationRecovery.shouldRemove(content("", info: ["aps": ["alert": "You have a new message"]])), "Recognize unexpanded raw alert text")
        expect(!RGNotificationRecovery.shouldRemove(content("You have a new message", title: "Alice", info: [RGNotificationRecovery.resolvedKey: true])), "Preserve deliberate locked-app privacy previews")
        expect(!RGNotificationRecovery.shouldRemove(content("You have a new message", title: "Regram", info: ["peerId": "123", RGNotificationRecovery.resolvedKey: true])), "Preserve a real message with exactly the same body")
        expect(!RGNotificationRecovery.shouldRemove(content("You have a new message", title: "Alice")), "Do not erase identifiable legacy message notifications")
        expect(!RGNotificationRecovery.shouldRemove(content("You have a new message", title: "Regram")), "An app title alone must not erase a legacy privacy preview")
        expect(RGNotificationRecovery.shouldRemove(content("You have a new message", title: "Group", info: ["p": "synthetic"])), "Unresolved encrypted placeholders can also carry a title")
        expect(!RGNotificationRecovery.shouldRemove(content("You have a new message from me", title: "Regram")), "Match the whole placeholder rather than arbitrary prefixes")
        expect(!RGNotificationRecovery.isPlaceholder(title: "Regram", body: "You have a new message", userInfo: [:], hasAttachments: true), "Preserve attachment notifications")
        let old = content(""); old.threadIdentifier = "empty-notification"
        expect(RGNotificationRecovery.shouldRemove(old), "Continue clearing old-version quiet markers")
        let quiet = RGNotificationRecovery.quietContent(badge: 7)
        expect(quiet.title.trimmingCharacters(in: .whitespacesAndNewlines) == "Regram" && quiet.body.isEmpty && quiet.subtitle.isEmpty, "Use a valid nonblank passive title to avoid restoring the original APNs body")
        expect(quiet.sound == nil && quiet.badge == 7 && quiet.userInfo.count == 1 && quiet.attachments.isEmpty, "Quiet fallback retains only badge and recovery metadata")
        expect(RGNotificationRecovery.shouldRemove(quiet), "Quiet fallbacks remain removable")
        let budget = RGNotificationResourceBudget()
        expect(!budget.reserve(size: 0) && !budget.reserve(size: -1), "Invalid sizes must not enter fetches")
        expect(!budget.reserve(size: 3 * 1024 * 1024), "Reject large resources before buffering")
        expect(budget.reserve(size: nil) && budget.reserve(size: nil) && budget.reserve(size: nil) && !budget.reserve(size: 1), "All enrichment shares one bounded request budget")
        expect(RGNotificationResourceBudget.permitsChunk(offset: 1024, count: 1024, lowerBound: 0, upperBound: 1024, maximumBytes: 2048), "Allow a complete bounded chunk")
        expect(!RGNotificationResourceBudget.permitsChunk(offset: Int64.max, count: 1, lowerBound: 0, upperBound: 1, maximumBytes: 2048), "Reject overflowing resource offsets before allocating")
        expect(!RGNotificationResourceBudget.permitsChunk(offset: 0, count: 3, lowerBound: 0, upperBound: 4, maximumBytes: 2048), "Reject invalid source ranges")
        expect(!RGNotificationResourceBudget.permitsChunk(offset: 2000, count: 100, lowerBound: 0, upperBound: 100, maximumBytes: 2048), "Reject bytes beyond the admitted resource size")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("resource")
        try! Data(repeating: 1, count: 32).write(to: file)
        expect(RGNotificationResourceBudget.cachedData(path: file.path)?.count == 32 && RGNotificationResourceBudget.cachedFileIsWithinBudget(path: file.path), "Read small cached resources normally")
        try! Data(repeating: 1, count: 2 * 1024 * 1024 + 1).write(to: file)
        expect(RGNotificationResourceBudget.cachedData(path: file.path) == nil && !RGNotificationResourceBudget.cachedFileIsWithinBudget(path: file.path), "Do not load oversized cached resources")
        if #available(macOS 12.0, iOS 15.0, *) { expect(quiet.interruptionLevel == .passive && quiet.relevanceScore == 0, "Use passive delivery without sound") }
        print("Notification recovery passed: signing/profile mismatch, retained filtering, placeholder detection, privacy previews, real-message collisions and valid quiet fallback.")
    }
}

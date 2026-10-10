import Foundation

extension UserDefaults {
    public static let rgTestStandard = UserDefaults(suiteName: ProcessInfo.processInfo.environment["RG_TEST_SUITE"]! + "-standard")!
}

@main enum SettingsRuntimeTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() throws {
        let settings = RGSimpleSettings.shared
        let suite = ProcessInfo.processInfo.environment["RG_TEST_SUITE"]!
        defer {
            UserDefaults.rgTestStandard.removePersistentDomain(forName: suite + "-standard")
            UserDefaults(suiteName: suite + "-group")!.removePersistentDomain(forName: suite + "-group")
        }
        UserDefaults.rgTestStandard.set("synthetic", forKey: "api_hash")
        settings.panguSpacing = false
        settings.defaultOutgoingFormatting = "none"
        settings.fontFamily = "inter"
        settings.messageFilterRules = [RGMessageFilterRule(pattern: "spam", isEnabled: false)]
        let backup = settings.exportPreferences(categories: Set(RGBackupCategory.allCases))
        expect(backup.values["api_hash"] == nil && backup.values["status"] == nil && backup.values["primaryUserId"] == nil, "Export must include allowlisted preferences only")
        let decoded = try RGSettingsBackup.decode(backup.encoded())
        expect(decoded.values == backup.values, "All exported defaults must round-trip with correct types")
        settings.fontFamily = "lora"
        settings.panguSpacing = true
        settings.messageFilterRules = [RGMessageFilterRule(pattern: "different")]
        _ = settings.messageFilterRules; _ = settings.fontFamily
        let generation = settings.contentFilterGeneration
        settings.applyPreferences(decoded.values)
        expect(settings.fontFamily == "inter" && !settings.panguSpacing, "Restore must invalidate cached wrappers immediately")
        expect(settings.messageFilterRules.count == 1 && !settings.messageFilterRules[0].isEnabled && settings.contentFilterGeneration > generation, "Restore must invalidate derived filter caches")
        settings.setChatPreferences(RGChatPreferences(formatting: "bold", panguSpacing: true), accountId: 1, peerId: 5)
        expect(settings.defaultOutgoingFormat(accountId: 1, peerId: 5) == .bold && settings.panguSpacing(accountId: 1, peerId: 5), "Chat overrides must affect the selected account/chat")
        expect(settings.defaultOutgoingFormat(accountId: 2, peerId: 5) == .none && !settings.panguSpacing(accountId: 2, peerId: 5), "Another account must retain global preferences")
        settings.setChatPreferences(RGChatPreferences(), accountId: 1, peerId: 5)
        expect(settings.chatPreferencesSnapshot.isEmpty, "Resetting an override must remove stale cached chat preferences")
        settings.applyPreferences(["downloadSpeedBoost": .string("maximum")])
        expect(settings.downloadSpeedBoost == "medium", "Restore must never reintroduce the removed maximum download tier")
        settings.applyPreferences([:], resetCategories: [.appearance])
        expect(settings.fontFamily == "system" && settings.defaultOutgoingFormatting == "none", "Category reset must restore its defaults while preserving other categories")
        let selected = decoded.selectedValues(categories: [.media])
        expect(!selected.isEmpty && selected.keys.allSatisfy { RGSettingsBackup.category(for: $0) == .media }, "Import preview category selection must constrain writes")
        let bad = RGSettingsBackup(values: ["tabBarWidthPercent": .integer(Int64.max)])
        do { _ = try RGSettingsBackup.decode(bad.encoded()); fatalError("Out-of-range settings must be rejected") } catch {}
        do { _ = try RGSettingsBackup.decode(Data(repeating: 0, count: RGSettingsBackup.maximumBytes + 1)); fatalError("Oversized backup must be rejected") } catch {}
        let hide = RGMessageFilterRule(pattern: "spam")
        let keep = RGMessageFilterRule(pattern: "approved", isException: true)
        expect(RGNotificationFilterPolicy.shouldHide(text: "spam", senderId: 3, peerId: 5, isIncoming: true, rules: [hide], hiddenSenders: [], disabledChats: []), "Notifications must use the same keyword rules")
        expect(!RGNotificationFilterPolicy.shouldHide(text: "spam approved", senderId: 3, peerId: 5, isIncoming: true, rules: [hide, keep], hiddenSenders: [], disabledChats: []), "Notification whitelist must override keyword hides")
        expect(RGNotificationFilterPolicy.shouldHide(text: "approved", senderId: 3, peerId: 5, isIncoming: true, rules: [keep], hiddenSenders: [3], disabledChats: [5]), "Hidden senders must remain hidden in notifications")
        expect(!RGNotificationFilterPolicy.shouldHide(text: "spam", senderId: 3, peerId: 5, isIncoming: false, rules: [hide], hiddenSenders: [3], disabledChats: []), "Outgoing content must not be filtered as a new-message push")
        let stats = RGTransferStatistics()
        stats.recordReceived(byteCount: 1000, now: 10)
        stats.recordReceived(byteCount: 1000, now: 11)
        expect(stats.snapshot(now: 12).receivedBytes == 2000 && stats.snapshot(now: 12).bytesPerSecond == 1000, "Transfer rate must reflect payload within the moving window")
        expect(stats.snapshot(now: 20).bytesPerSecond == 0 && stats.snapshot(now: 20).receivedBytes == 2000, "Idle rate must fall to zero while cumulative bytes remain")
        let reveal = RGTemporaryRevealState()
        let first = reveal.begin(accountId: 1, peerId: 5, seconds: 10, now: 100)
        expect(reveal.visiblePeerIds(accountId: 1, now: 105) == [5] && reveal.visiblePeerIds(accountId: 2, now: 105).isEmpty, "Temporary recovery must be scoped to the account")
        let replacement = reveal.begin(accountId: 1, peerId: 5, seconds: 10, now: 105)
        expect(!reveal.end(accountId: 1, peerId: 5, ticket: first) && reveal.visiblePeerIds(accountId: 1, now: 111) == [5], "An old expiration callback must not end a newer reveal")
        expect(reveal.visiblePeerIds(accountId: 1, now: 116).isEmpty && reveal.end(accountId: 1, peerId: 5, ticket: replacement), "Recovery must expire and retain safe ticket cleanup")
        print("Settings runtime checks passed: real wrappers/derived cache restore, allowlist, categories, malformed limits, chat/account overrides, notification predicates and transfer estimates")
    }
}

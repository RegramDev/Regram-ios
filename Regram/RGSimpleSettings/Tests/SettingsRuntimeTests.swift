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
        expect(!settings.messageSummaryEnabled, "Summary actions must be opt-in")
        settings.messageSummaryEnabled = true
        expect(!settings.automaticallyRevealSpoilers, "Spoilers must remain concealed by default")
        settings.automaticallyRevealSpoilers = true
        settings.panguSpacing = false
        settings.defaultOutgoingFormatting = "none"
        settings.fontFamily = "inter"
        settings.messageFilterRules = [RGMessageFilterRule(pattern: "spam", isEnabled: false)]
        expect(!settings.networkPolicy.dohEnabled && settings.networkPolicy.ipVersion == .automatic, "Custom DNS must be opt-in")
        expect(!RGNetworkPolicy.validEndpoint("http://example.com/dns-query") && !RGNetworkPolicy.validEndpoint("https://name:password@example.com/dns-query") && !RGNetworkPolicy.validEndpoint("https://example.com/dns-query#fragment"), "DoH requires a credential-free HTTPS endpoint")
        expect(RGNetworkPolicy.validEndpoint("https://example.com/dns-query"), "Valid HTTPS DoH endpoint")
        settings.networkPolicy = RGNetworkPolicy(dohEnabled: true, endpoint: "https://example.com/dns-query", ipVersion: .ipv6)
        expect(RGNetworkPolicy(defaults: UserDefaults(suiteName: suite + "-group")!).ipVersion == .ipv6, "Transport preference must reach the extension")
        let group = UserDefaults(suiteName: suite + "-group")!
        settings.localDNSForProxyHost = true
        expect(!settings.networkPolicy.dohEnabled && settings.localDNSForProxyHost && !group.bool(forKey: "customDoHEnabled") && group.bool(forKey: "localDNSForProxyHost"), "System DNS must disable DoH in both backing stores")
        settings.networkPolicy = RGNetworkPolicy(dohEnabled: true, endpoint: "https://example.com/dns-query", ipVersion: .ipv6)
        expect(!settings.localDNSForProxyHost && !group.bool(forKey: "localDNSForProxyHost"), "DoH must disable system DNS in both backing stores")
        settings.applyPreferences(["customDoHEnabled": .bool(true), "localDNSForProxyHost": .bool(true)])
        expect(settings.networkPolicy.dohEnabled && !settings.localDNSForProxyHost && !group.bool(forKey: "localDNSForProxyHost"), "Conflicting imported DNS choices must normalize before reconnect")
        expect(RGNetworkPolicy(dohEnabled: true, endpoint: "bad").effectiveEndpoint == "invalid-doh-endpoint", "Invalid enabled DoH must fail closed, not silently downgrade")
        settings.summaryLLMModel = "independent-model"; settings.summaryLLMPrompt = "summary @text"
        expect(settings.translationLLMModel.isEmpty && settings.translationLLMPrompt != settings.summaryLLMPrompt, "Summary and translation must have independent configuration")
        let backup = settings.exportPreferences(categories: Set(RGBackupCategory.allCases))
        expect(backup.values["api_hash"] == nil && backup.values["status"] == nil && backup.values["primaryUserId"] == nil, "Export must include allowlisted preferences only")
        expect(backup.selectedValues(categories: [.messages])["automaticallyRevealSpoilers"] == .bool(true), "Spoiler display must persist in message settings backups")
        let decoded = try RGSettingsBackup.decode(backup.encoded())
        expect(decoded.values == backup.values, "All exported defaults must round-trip with correct types")
        settings.fontFamily = "lora"
        settings.automaticallyRevealSpoilers = false
        settings.panguSpacing = true
        settings.messageFilterRules = [RGMessageFilterRule(pattern: "different")]
        _ = settings.messageFilterRules; _ = settings.fontFamily
        let generation = settings.contentFilterGeneration
        settings.applyPreferences(decoded.values)
        expect(settings.automaticallyRevealSpoilers, "Restore must immediately reload the spoiler display preference")
        expect(settings.messageSummaryEnabled && settings.summaryLLMModel == "independent-model", "Summary preferences must round-trip")
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
        settings.applyPreferences([:], resetCategories: [.messages])
        expect(!settings.messageSummaryEnabled, "Reset must remove summary actions")
        expect(!settings.automaticallyRevealSpoilers, "Reset must restore concealed spoilers instead of keeping an automatic reveal")
        let selected = decoded.selectedValues(categories: [.media])
        expect(!selected.isEmpty && selected.keys.allSatisfy { RGSettingsBackup.category(for: $0) == .media }, "Import preview category selection must constrain writes")
        let bad = RGSettingsBackup(values: ["tabBarWidthPercent": .integer(Int64.max)])
        do { _ = try RGSettingsBackup.decode(bad.encoded()); fatalError("Out-of-range settings must be rejected") } catch {}
        do { _ = try RGSettingsBackup.decode(Data(repeating: 0, count: RGSettingsBackup.maximumBytes + 1)); fatalError("Oversized backup must be rejected") } catch {}
        settings.applyPreferences([:], resetCategories: [.media])
        expect(!settings.networkPolicy.dohEnabled && RGNetworkPolicy(defaults: UserDefaults(suiteName: suite + "-group")!).ipVersion == .automatic, "Transport reset must update the extension too")
        let hide = RGMessageFilterRule(pattern: "spam")
        let keep = RGMessageFilterRule(pattern: "approved", isException: true)
        expect(RGNotificationFilterPolicy.shouldHide(text: "spam", senderId: 3, peerId: 5, isIncoming: true, rules: [hide], hiddenSenders: [], disabledChats: []), "Notifications must use the same keyword rules")
        expect(!RGNotificationFilterPolicy.shouldHide(text: "spam approved", senderId: 3, peerId: 5, isIncoming: true, rules: [hide, keep], hiddenSenders: [], disabledChats: []), "Notification whitelist must override keyword hides")
        expect(RGNotificationFilterPolicy.shouldHide(text: "approved", senderId: 3, peerId: 5, isIncoming: true, rules: [keep], hiddenSenders: [3], disabledChats: [5]), "Hidden senders must remain hidden in notifications")
        expect(!RGNotificationFilterPolicy.shouldHide(text: "spam", senderId: 3, peerId: 5, isIncoming: false, rules: [hide], hiddenSenders: [3], disabledChats: []), "Outgoing content must not be filtered as a new-message push")
        let stats = RGTransferStatistics()
        stats.recordReceived(byteCount: 1000, now: 10)
        stats.recordReceived(byteCount: 1000, now: 11)
        expect(stats.snapshot(now: 12).receivedBytes == 2000 && abs(stats.snapshot(now: 12).bytesPerSecond - 2000.0 / 3.0) < 0.001, "Transfer rate must use the fixed three-second window")
        expect(stats.snapshot(now: 20).bytesPerSecond == 0 && stats.snapshot(now: 20).receivedBytes == 2000, "Idle rate must fall to zero while cumulative bytes remain")
        let reveal = RGTemporaryRevealState()
        let first = reveal.begin(accountId: 1, peerId: 5, seconds: 10, now: 100)
        expect(reveal.visiblePeerIds(accountId: 1, now: 105) == [5] && reveal.visiblePeerIds(accountId: 2, now: 105).isEmpty, "Temporary recovery must be scoped to the account")
        let replacement = reveal.begin(accountId: 1, peerId: 5, seconds: 10, now: 105)
        expect(!reveal.end(accountId: 1, peerId: 5, ticket: first) && reveal.visiblePeerIds(accountId: 1, now: 111) == [5], "An old expiration callback must not end a newer reveal")
        expect(reveal.visiblePeerIds(accountId: 1, now: 116).isEmpty && reveal.end(accountId: 1, peerId: 5, ticket: replacement), "Recovery must expire and retain safe ticket cleanup")
        let originalMenuOrder = settings.contextMenuOrder
        let initialMenu = settings.availableContextMenuItems(accountPeerId: 111)
        expect(initialMenu.contains(.copy) && !initialMenu.contains(.editSuggestedPostPrice) && !initialMenu.contains(.sendLogs), "Customization must start with implemented regular actions, not rare/diagnostic placeholders")
        settings.recordAvailableContextMenuItems([.editSuggestedPostPrice, .sendLogs, .sendMoney], accountPeerId: 111)
        expect(settings.availableContextMenuItems(accountPeerId: 111).contains(.editSuggestedPostPrice), "A conditional menu item must appear after it is actually generated")
        expect(!settings.availableContextMenuItems(accountPeerId: 111).contains(.sendLogs) && !settings.availableContextMenuItems(accountPeerId: 111).contains(.sendMoney), "Diagnostics and wallet actions must stay out of customization")
        expect(!settings.availableContextMenuItems(accountPeerId: 222).contains(.editSuggestedPostPrice), "Another account must not inherit unavailable conditional menu items")
        settings.contextMenuOrder = [.copy, .viewStats, .reply]
        settings.reorderVisibleContextMenuItems([.reply, .copy])
        expect(Array(settings.contextMenuOrder.prefix(3)) == [.reply, .viewStats, .copy], "Reordering visible items must preserve the position of hidden actions")
        settings.contextMenuOrder = originalMenuOrder
        print("Settings runtime checks passed: storage/backup regressions, account-scoped real-menu inventory, and reordering with hidden actions")
    }
}

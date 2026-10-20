import Foundation

extension UserDefaults {
    public static let rgTestStandard = UserDefaults(suiteName: ProcessInfo.processInfo.environment["RG_TEST_SUITE"]! + "-standard")!
}

@main enum SettingsRuntimeTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() throws {
        // An installed three-line value must migrate before the singleton caches its wrappers.
        UserDefaults.rgTestStandard.set("3", forKey: "chatListLines")
        let settings = RGSimpleSettings.shared
        let suite = ProcessInfo.processInfo.environment["RG_TEST_SUITE"]!
        defer {
            UserDefaults.rgTestStandard.removePersistentDomain(forName: suite + "-standard")
            UserDefaults(suiteName: suite + "-group")!.removePersistentDomain(forName: suite + "-group")
        }
        UserDefaults.rgTestStandard.set("synthetic", forKey: "api_hash")
        expect(RGSimpleSettings.ChatListLines.allCases.map(\.rawValue).sorted() == ["1", "2"], "Only one- and two-line modes are offered")
        expect(settings.chatListLines == "2" && UserDefaults.rgTestStandard.string(forKey: "chatListLines") == "2", "Persistently migrate a removed three-line value")
        settings.chatListLines = "1"
        expect(settings.chatListLines == "1", "Keep the one-line selection")
        settings.applyPreferences(["chatListLines": .string("3")])
        expect(settings.chatListLines == "2" && UserDefaults.rgTestStandard.string(forKey: "chatListLines") == "2", "Old backups must not restore an unsupported line mode")
        expect(settings.exportPreferences(categories: [.appearance]).values["chatListLines"] == .string("2"), "Export must not retain the removed three-line value")
        settings.chatListLines = "2"
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
        for version in RGNetworkPolicy.IPVersion.allCases {
            var policy = settings.networkPolicy; policy.ipVersion = version; policy.disableBackupAddresses = true
            for mode in RGNetworkPolicy.DNSMode.allCases {
                policy.dnsMode = mode; settings.networkPolicy = policy
                expect(settings.networkPolicy == policy && RGNetworkPolicy(defaults: group) == policy, "All five IP policies and three DNS modes must persist to both stores")
            }
        }
        expect(RGNetworkPolicy.IPVersion.ipv4.rawValue == 4 && RGNetworkPolicy.IPVersion.ipv6.rawValue == 6, "Existing preferred-mode values must retain their meaning")
        settings.revokedMarker = RGRevokedMarker(style: .text, text: "  test\n撤回  ", color: "aabbCC")
        expect(settings.revokedMarker == RGRevokedMarker(style: .text, text: "test撤回", color: "#AABBCC"), "Marker text and color must normalize before storage")
        expect(RGRevokedMarker(style: .text).label(defaultText: "Deleted") == "Deleted" && RGRevokedMarker(style: .none).label(defaultText: "Deleted") == nil, "Blank text uses localization; hidden marker adds no prefix")
        expect(RGRevokedMarker.rgb("#000000") == 0 && RGRevokedMarker.rgb("#12345Z") == nil, "Black is valid; malformed marker colors are rejected")
        expect(RGRevokedMarker.normalizedText("a\u{202e}b") == "ab" && RGRevokedMarker.normalizedText(String(repeating: "哈", count: 30)).count == 24, "Marker text must not inject control characters or unbounded timestamp text")
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
        expect(settings.revokedMarker.text == "test撤回" && settings.revokedMarker.color == "#AABBCC", "Marker preferences must restore from backups")
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
        expect(!settings.networkPolicy.disableBackupAddresses && !RGNetworkPolicy(defaults: group).disableBackupAddresses, "Backup discovery reset must reach extensions")
        expect(!settings.networkPolicy.dohEnabled && RGNetworkPolicy(defaults: UserDefaults(suiteName: suite + "-group")!).ipVersion == .automatic, "Transport reset must update the extension too")
        settings.applyPreferences([:], resetCategories: [.privacy])
        expect(settings.revokedMarker == RGRevokedMarker(), "Reset restores the original icon marker")
        Self.checkIconSwitching()
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
        expect(!settings.chatToolsEnabled && !settings.autoInlineBotEnabled && !settings.chatSearchFieldAtBottom, "New interaction and external-query modes must be opt-in")
        settings.rememberLastFolder = true
        expect(settings.chatListStartupFolderModeValue == .last, "Existing remember-last choice remains effective before selecting a startup mode")
        settings.rememberLastFolder = false
        settings.chatListSwipeAction = "switch"
        expect(settings.chatListSwipeActionMode.allowsFolderSwitch && !settings.chatListSwipeActionMode.allowsQuickActions && !settings.disableChatSwipeOptions, "Folder-only gestures preserve the legacy master state")
        settings.chatListSwipeAction = "none"
        expect(!settings.chatListSwipeActionMode.allowsFolderSwitch && !settings.chatListSwipeActionMode.allowsQuickActions && settings.disableChatSwipeOptions, "Disabled gestures must agree across old/new paths")
        settings.chatListSwipeAction = "both"
        settings.setChatListStartupSpecificFolderId(27, accountPeerId: 111)
        settings.setChatListStartupSpecificFolderId(35, accountPeerId: 222)
        expect(settings.chatListStartupSpecificFolderId(accountPeerId: 111) == 27 && settings.chatListStartupSpecificFolderId(accountPeerId: 222) == 35, "Fixed startup folders are isolated by account")
        settings.hideSavedAndArchivedMessagesInList = true
        settings.disableCommunityChatGrouping = true
        expect(RGFeaturePreferences.storage(for: "features.disableCommunityChatGrouping").bool(forKey: "features.disableCommunityChatGrouping"), "Grouping policy must be readable from the shared store used by extensions")
        settings.enablePanguOnReceiving = true
        settings.setGroupProfileSettingItemVisible(.permissions, visible: true)
        settings.setTextStyleMenuItemEnabled(.bold, enabled: true)
        let featuresBackup = settings.exportPreferences(categories: Set(RGBackupCategory.allCases))
        expect(featuresBackup.values["features.hideSavedAndArchivedMessagesInList"] == .bool(true) && featuresBackup.values["features.textStyleMenu.enabled"] == .string("bold"), "New privacy and composer choices participate in normal backups")
        expect(settings.exportPreferences(categories: [.privacy]).values["features.hideSavedAndArchivedMessagesInList"] == .bool(true) && settings.exportPreferences(categories: [.appearance]).values["features.hideSavedAndArchivedMessagesInList"] == nil, "Privacy enhancements must stay in the selected backup category")
        expect(featuresBackup.values["features.startupFolders"] == .dictionary(["111": "27", "222": "35"]), "Fixed-folder account mapping must survive settings backup")
        expect(featuresBackup.values.keys.allSatisfy { !$0.lowercased().contains("icloud") && !$0.lowercased().contains("sessionbackup") }, "Excluded cloud/session features must not enter export")
        settings.applyPreferences(featuresBackup.values, resetCategories: [.appearance])
        expect(settings.hideSavedAndArchivedMessagesInList && settings.isGroupProfileSettingItemVisible(.permissions) && settings.isTextStyleMenuItemEnabled(.bold), "Import and reset retain new feature choices")
        expect(settings.chatListStartupSpecificFolderId(accountPeerId: 111) == 27, "Import restores the per-account startup folder")
        let panguOriginal = "😀中文Telegram世界"
        let pangu = RGFeaturePangu.transform(panguOriginal)
        let originalRange = (panguOriginal as NSString).range(of: "Telegram")
        let mapped = RGFeaturePangu.transformRange(originalRange.location ..< (originalRange.location + originalRange.length), insertedUtf16Offsets: pangu.insertedUtf16Offsets)
        expect((pangu.text as NSString).substring(with: NSRange(location: mapped.lowerBound, length: mapped.count)) == "Telegram", "Received display spacing must preserve emoji-aware UTF-16 entity ranges")
        let restored = RGFeaturePangu.reverseTransformRange(mapped, insertedUtf16Offsets: pangu.insertedUtf16Offsets, originalLength: (panguOriginal as NSString).length)
        expect(restored == originalRange.location ..< (originalRange.location + originalRange.length), "Copying a displayed entity must recover its original range")
        let protectedText = NSMutableAttributedString(string: "中文Telegram世界")
        protectedText.addAttribute(NSAttributedString.Key("Attribute__Monospace"), value: true, range: NSRange(location: 2, length: 8))
        let protectedResult = RGFeaturePangu.transform(protectedText)
        var protectedSegments: [String] = []
        protectedResult.enumerateAttribute(NSAttributedString.Key("Attribute__Monospace"), in: NSRange(location: 0, length: protectedResult.length)) { value, range, _ in
            if value != nil { protectedSegments.append((protectedResult.string as NSString).substring(with: range)) }
        }
        expect(protectedSegments == ["Telegram"], "Pangu insertion must not alter protected code content or lose its attributes")
        print("Settings runtime checks passed: storage/backup regressions, account-scoped real-menu inventory, and reordering with hidden actions")
    }
    static func checkIconSwitching() {
        expect(RGAppIconNames.canonicalName("SGSilver") == "RGSilver" && RGAppIconNames.canonicalName("SGAnime") == "RGDefault" && RGAppIconNames.canonicalName("RGAnime") == "RGDefault", "Legacy artwork names must select the correct picker item")
        var actual: String?; var applies: [(String?, (Bool) -> Void)] = []; var timeouts: [() -> Void] = []; var updates = 0; var results: [Bool] = []
        let coordinator = RGAppIconSwitchCoordinator(current: { actual }, apply: { applies.append(($0, $1)) }, changed: { updates += 1 }, schedule: { _, action in timeouts.append(action) })
        coordinator.request("RGBlack") { results.append($0) }
        coordinator.request("RGWhite") { results.append($0) }
        coordinator.request("RGGold") { results.append($0) }
        expect(applies.count == 1 && results == [true], "Concurrent taps must queue only the latest requested icon")
        actual = "RGBlack"; applies[0].1(true)
        expect(applies.count == 2 && applies[1].0 == "RGGold", "Finish the active request before applying the newest tap")
        actual = "RGGold"; applies[1].1(true)
        coordinator.request("RGGold") { results.append($0) }
        expect(applies.count == 2 && results.allSatisfy { $0 }, "Selecting the active icon must complete without a UIKit request")
        coordinator.request("RGWhite") { results.append($0) }; applies[2].1(true)
        expect(results.last == true && coordinator.currentIconName == "RGWhite", "A successful UIKit completion must not be rejected because its getter still returns the old icon")
        coordinator.request("RGPro") { results.append($0) }; timeouts.last?()
        expect(results.last == false, "Interrupted callbacks must release the request lock")
        coordinator.request(nil) { results.append($0) }
        let count = results.count; applies[3].1(false)
        expect(results.count == count, "Late callbacks must not complete a newer request")
        actual = nil; applies[4].1(true); coordinator.resume()
        actual = "SGDefault"
        coordinator.request(nil) { results.append($0) }
        expect(applies.count == 6 && applies[5].0 == nil, "Restoring primary must replace an old alternate named Default")
        actual = nil; applies[5].1(true)
        expect(results.last == true && updates >= 5, "Restoring primary must read the system and notify all icon views")
    }

}

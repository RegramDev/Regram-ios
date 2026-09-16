import Foundation
import RGAppGroupIdentifier
import RGLogging

let APP_GROUP_IDENTIFIER = rgAppGroupIdentifier()

public class RGSimpleSettings {
    
    public static let shared = RGSimpleSettings()
    
    private init() {
        setDefaultValues()
        migrate()
        preCacheValues()
    }
    
    private func setDefaultValues() {
        UserDefaults.standard.register(defaults: RGSimpleSettings.defaultValues)
        // Just in case group defaults will be nil
        UserDefaults.standard.register(defaults: RGSimpleSettings.groupDefaultValues)
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.register(defaults: RGSimpleSettings.groupDefaultValues)
        }
    }
    
    private func migrate() {
        let showRepostToStoryMigrationKey = "migrated_\(Keys.showRepostToStory.rawValue)"
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            if !groupUserDefaults.bool(forKey: showRepostToStoryMigrationKey) {
                self.showRepostToStoryV2 = self.showRepostToStory
                groupUserDefaults.set(true, forKey: showRepostToStoryMigrationKey)
                RGLogger.shared.log("SGSimpleSettings", "Migrated showRepostToStory. \(self.showRepostToStory) -> \(self.showRepostToStoryV2)")
            }
        } else {
            RGLogger.shared.log("SGSimpleSettings", "Unable to migrate showRepostToStory. Shared UserDefaults suite is not available for '\(APP_GROUP_IDENTIFIER)'.")
        }

        // MARK: Regram — message filter v2. Plain keywords become all-chat substring rules.
        let messageFilterRulesMigrationKey = "migrated_\(Keys.messageFilterRules.rawValue)"
        if !UserDefaults.standard.bool(forKey: messageFilterRulesMigrationKey) {
            let legacyKeywords = self.messageFilterKeywords
            if !legacyKeywords.isEmpty, self.messageFilterRules.isEmpty {
                self.messageFilterRules = legacyKeywords.map { RGMessageFilterRule(pattern: $0) }
                RGLogger.shared.log("SGSimpleSettings", "Migrated \(legacyKeywords.count) messageFilterKeywords -> messageFilterRules")
            }
            UserDefaults.standard.set(true, forKey: messageFilterRulesMigrationKey)
        }

        let chatListLinesMigrationKey = "migrated_\(Keys.chatListLines.rawValue)"
        if !UserDefaults.standard.bool(forKey: chatListLinesMigrationKey) {
            let legacyCompactMessagePreviewKey = "compactMessagePreview"
            if UserDefaults.standard.object(forKey: legacyCompactMessagePreviewKey) != nil {
                if UserDefaults.standard.bool(forKey: legacyCompactMessagePreviewKey) {
                    self.chatListLines = ChatListLines.one.rawValue
                }
                UserDefaults.standard.removeObject(forKey: legacyCompactMessagePreviewKey)
                RGLogger.shared.log("SGSimpleSettings", "Migrated compactMessagePreview -> chatListLines. \(self.chatListLines)")
            }
            UserDefaults.standard.set(true, forKey: chatListLinesMigrationKey)
        }
    }
    
    private func preCacheValues() {
        // let dispatchGroup = DispatchGroup()

        let tasks = [
//            { let _ = self.allChatsFolderPositionOverride },
            { let _ = self.tabBarSearchEnabled },
            { let _ = self.allChatsHidden },
            { let _ = self.hideTabBar },
            { let _ = self.bottomTabStyle },
            { let _ = self.compactChatList },
            { let _ = self.chatListLines },
            { let _ = self.compactFolderNames },
            { let _ = self.disableSwipeToRecordStory },
            { let _ = self.rememberLastFolder },
            { let _ = self.quickTranslateButton },
            { let _ = self.stickerSize },
            { let _ = self.stickerTimestamp },
            { let _ = self.hideReactions },
            { let _ = self.disableGalleryCamera },
            { let _ = self.disableSendAsButton },
            { let _ = self.disableSnapDeletionEffect },
            { let _ = self.startTelescopeWithRearCam },
            { let _ = self.hideRecordingButton },
            { let _ = self.inputToolbar },
            { let _ = self.dismissedSGSuggestions },
            { let _ = self.customAppBadge }
        ]

        tasks.forEach { task in
            DispatchQueue.global(qos: .background).async(/*group: dispatchGroup*/) {
                task()
            }
        }

        // dispatchGroup.notify(queue: DispatchQueue.main) {}
    }
    
    public func synchronizeShared() {
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.synchronize()
        }
    }
    
    public enum Keys: String, CaseIterable {
        case hidePhoneInSettings
        case showTabNames
        case startTelescopeWithRearCam
        case accountColorsSaturation
        case uploadSpeedBoost
        case downloadSpeedBoost
        case bottomTabStyle
        case rememberLastFolder
        case lastAccountFolders
        case localDNSForProxyHost
        case sendLargePhotos
        case outgoingPhotoQuality
        case storyStealthMode
        case canUseStealthMode
        case disableSwipeToRecordStory
        case quickTranslateButton
        case outgoingLanguageTranslation
        case hideReactions
        case showRepostToStory
        case showRepostToStoryV2
        case contextShowSelectFromUser
        case contextShowSaveToCloud
        case contextShowRestrict
        // case contextShowBan
        case contextShowHideForwardName
        case contextShowReport
        case contextShowReply
        case contextShowPin
        case contextShowSaveMedia
        case contextShowMessageReplies
        case contextShowJson
        // MARK: Regram
        case contextShowRepeatForward
        case contextShowRepeatCopy
        case contextMenuOrder
        case profileDefaultTabGroupsInCommon
        case mentionAsUserIdLink
        case localPremium
        case localPremiumEmojiStatus
        case nsfwEnabled
        case nsfwAgeConfirmed
        case disableLinkPreview
        case disableScrollToNextChannel
        case disableScrollToNextTopic
        case disableChatSwipeOptions
        case disableDeleteChatSwipeOption
        case disableGalleryCamera
        case disableGalleryCameraPreview
        case disableSendAsButton
        case disableSnapDeletionEffect
        case stickerSize
        case stickerTimestamp
        case hideRecordingButton
        case hideTabBar
        case showDC
        case showCreationDate
        case showRegDate
        case regDateCache
        case compactChatList
        case chatListLines
        case compactFolderNames
        case allChatsTitleLengthOverride
//        case allChatsFolderPositionOverride
        case allChatsHidden
        case defaultEmojisFirst
        case messageDoubleTapActionOutgoing
        case wideChannelPosts
        case forceEmojiTab
        case forceBuiltInMic
        case secondsInMessages
        case hideChannelBottomButton
        case forceSystemSharing
        case confirmCalls
        case videoPIPSwipeDirection
        case legacyNotificationsFix
        case messageFilterKeywords
        case messageFilterRules
        case blockedPeerIds
        case messageFilterDisabledPeerIds
        case inputToolbar
        case pinnedMessageNotifications
        case mentionsAndRepliesNotifications
        case primaryUserId
        case status
        case dismissedSGSuggestions
        case duckyAppIconAvailable
        case transcriptionBackend
        case translationBackend
        case customAppBadge
        case canUseNY
        case nyStyle
        case wideTabBar
        case tabBarSearchEnabled
        case hideStories
        case disableAllAds
        case antiRevoke
        case antiAutoDelete
        case antiSelfDestruct
        case antiScreenshotNotification
        case allowSavingProtectedContent
        case allowDownloadingStories
        // MARK: Ghost Mode — suppress outgoing presence/activity signals
        case ghostDontReadMessages
        case ghostDontReadStories
        case ghostDontSendOnline
        case ghostDontSendTyping
        // MARK: Regram — insert a space between CJK and Latin/digits in outgoing text
        case panguSpacing
        case warnOnStoriesOpen
        case showProfileId
        case sendWithReturnKey
    }
    
    public enum DownloadSpeedBoostValues: String, CaseIterable {
        case none
        case medium
        case maximum
    }
    
    public enum BottomTabStyleValues: String, CaseIterable {
        case telegram
        case ios
    }
    
    public enum AllChatsTitleLengthOverride: String, CaseIterable {
        case none
        case short
        case long
    }
    
    public enum AllChatsFolderPositionOverride: String, CaseIterable {
        case none
        case last
        case hidden
    }

    public enum ChatListLines: String, CaseIterable {
        case three = "3"
        case two = "2"
        case one = "1"

        public static let defaultValue: ChatListLines = .three
    }
    
    public enum MessageDoubleTapAction: String, CaseIterable {
        case `default`
        case none
        case edit
    }
    
    public enum VideoPIPSwipeDirection: String, CaseIterable {
        case up
        case down
        case none
    }

    public enum TranscriptionBackend: String, CaseIterable {
        case `default`
        case apple
    }

    public enum TranslationBackend: String, CaseIterable {
        case `default`
        case gtranslate
        case google
        case system
        // Make sure to update TranslationConfiguration
    }
        
    public enum PinnedMessageNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }
    
    public enum MentionsAndRepliesNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }

    public enum NYStyle: String, CaseIterable {
        case `default`
        case snow
        case lightning
    }
    
    public static let defaultValues: [String: Any] = [
        Keys.hidePhoneInSettings.rawValue: true,
        Keys.showTabNames.rawValue: true,
        Keys.startTelescopeWithRearCam.rawValue: false,
        Keys.accountColorsSaturation.rawValue: 100,
        Keys.uploadSpeedBoost.rawValue: false,
        Keys.downloadSpeedBoost.rawValue: DownloadSpeedBoostValues.none.rawValue,
        Keys.rememberLastFolder.rawValue: false,
        Keys.bottomTabStyle.rawValue: BottomTabStyleValues.telegram.rawValue,
        Keys.lastAccountFolders.rawValue: [:],
        Keys.localDNSForProxyHost.rawValue: false,
        Keys.sendLargePhotos.rawValue: false,
        Keys.outgoingPhotoQuality.rawValue: 70,
        Keys.storyStealthMode.rawValue: false,
        Keys.canUseStealthMode.rawValue: true,
        Keys.disableSwipeToRecordStory.rawValue: false,
        Keys.quickTranslateButton.rawValue: false,
        Keys.outgoingLanguageTranslation.rawValue: [:],
        Keys.hideReactions.rawValue: false,
        Keys.showRepostToStory.rawValue: true,
        Keys.contextShowSelectFromUser.rawValue: true,
        Keys.contextShowSaveToCloud.rawValue: true,
        Keys.contextShowRestrict.rawValue: true,
        // Keys.contextShowBan.rawValue: true,
        Keys.contextShowHideForwardName.rawValue: true,
        Keys.contextShowReport.rawValue: true,
        Keys.contextShowReply.rawValue: true,
        Keys.contextShowPin.rawValue: true,
        Keys.contextShowSaveMedia.rawValue: true,
        Keys.contextShowMessageReplies.rawValue: true,
        Keys.contextShowJson.rawValue: false,
        // MARK: Regram
        Keys.contextShowRepeatForward.rawValue: true,
        Keys.contextShowRepeatCopy.rawValue: true,
        Keys.contextMenuOrder.rawValue: RGContextMenuItemId.allCases.map { $0.rawValue },
        Keys.profileDefaultTabGroupsInCommon.rawValue: false,
        Keys.mentionAsUserIdLink.rawValue: false,
        Keys.localPremium.rawValue: false,
        Keys.localPremiumEmojiStatus.rawValue: [:],
        Keys.nsfwEnabled.rawValue: false,
        Keys.nsfwAgeConfirmed.rawValue: false,
        Keys.disableLinkPreview.rawValue: false,
        Keys.disableScrollToNextChannel.rawValue: false,
        Keys.disableScrollToNextTopic.rawValue: false,
        Keys.disableChatSwipeOptions.rawValue: false,
        Keys.disableDeleteChatSwipeOption.rawValue: false,
        Keys.disableGalleryCamera.rawValue: false,
        Keys.disableGalleryCameraPreview.rawValue: false,
        Keys.disableSendAsButton.rawValue: false,
        Keys.disableSnapDeletionEffect.rawValue: false,
        Keys.stickerSize.rawValue: 100,
        Keys.stickerTimestamp.rawValue: true,
        Keys.hideRecordingButton.rawValue: false,
        Keys.hideTabBar.rawValue: false,
        Keys.showDC.rawValue: false,
        Keys.showCreationDate.rawValue: true,
        Keys.showRegDate.rawValue: true,
        Keys.regDateCache.rawValue: [:],
        Keys.compactChatList.rawValue: false,
        Keys.chatListLines.rawValue: ChatListLines.defaultValue.rawValue,
        Keys.compactFolderNames.rawValue: false,
        Keys.allChatsTitleLengthOverride.rawValue: AllChatsTitleLengthOverride.none.rawValue,
//        Keys.allChatsFolderPositionOverride.rawValue: AllChatsFolderPositionOverride.none.rawValue
        Keys.allChatsHidden.rawValue: false,
        Keys.defaultEmojisFirst.rawValue: false,
        Keys.messageDoubleTapActionOutgoing.rawValue: MessageDoubleTapAction.default.rawValue,
        Keys.wideChannelPosts.rawValue: false,
        Keys.forceEmojiTab.rawValue: false,
        Keys.hideChannelBottomButton.rawValue: false,
        Keys.secondsInMessages.rawValue: false,
        Keys.forceSystemSharing.rawValue: false,
        Keys.confirmCalls.rawValue: true,
        Keys.videoPIPSwipeDirection.rawValue: VideoPIPSwipeDirection.up.rawValue,
        Keys.messageFilterKeywords.rawValue: [],
        Keys.inputToolbar.rawValue: false,
        Keys.primaryUserId.rawValue: "",
        Keys.dismissedSGSuggestions.rawValue: [],
        Keys.duckyAppIconAvailable.rawValue: true,
        Keys.transcriptionBackend.rawValue: TranscriptionBackend.default.rawValue,
        Keys.translationBackend.rawValue: TranslationBackend.default.rawValue,
        Keys.customAppBadge.rawValue: "",
        Keys.canUseNY.rawValue: false,
        Keys.nyStyle.rawValue: NYStyle.default.rawValue,
        Keys.wideTabBar.rawValue: false,
        Keys.tabBarSearchEnabled.rawValue: true,
        Keys.hideStories.rawValue: false,
        Keys.disableAllAds.rawValue: false,
        Keys.antiRevoke.rawValue: false,
        Keys.antiAutoDelete.rawValue: false,
        Keys.antiSelfDestruct.rawValue: false,
        Keys.antiScreenshotNotification.rawValue: false,
        Keys.allowSavingProtectedContent.rawValue: false,
        Keys.allowDownloadingStories.rawValue: false,
        Keys.warnOnStoriesOpen.rawValue: false,
        Keys.showProfileId.rawValue: true,
        Keys.sendWithReturnKey.rawValue: false
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.legacyNotificationsFix.rawValue: false,
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.status.rawValue: 2, // Pro unlocked locally; see RGStatus.proStatus
        Keys.showRepostToStoryV2.rawValue: true,
        Keys.messageFilterRules.rawValue: "[]",
        Keys.blockedPeerIds.rawValue: [],
        Keys.messageFilterDisabledPeerIds.rawValue: [],
        // MARK: Ghost Mode — the app group suite, because the share/notification extensions run
        // TelegramCore too and must not leak a presence signal the main app is suppressing.
        Keys.ghostDontReadMessages.rawValue: false,
        Keys.ghostDontReadStories.rawValue: false,
        Keys.ghostDontSendOnline.rawValue: false,
        Keys.ghostDontSendTyping.rawValue: false,
        // MARK: Regram — pangu spacing.
        Keys.panguSpacing.rawValue: false,
    ]
    
    @UserDefault(key: Keys.hidePhoneInSettings.rawValue)
    public var hidePhoneInSettings: Bool
    
    @UserDefault(key: Keys.showTabNames.rawValue)
    public var showTabNames: Bool
    
    @UserDefault(key: Keys.startTelescopeWithRearCam.rawValue)
    public var startTelescopeWithRearCam: Bool
    
    @UserDefault(key: Keys.accountColorsSaturation.rawValue)
    public var accountColorsSaturation: Int32
    
    @UserDefault(key: Keys.uploadSpeedBoost.rawValue)
    public var uploadSpeedBoost: Bool
    
    @UserDefault(key: Keys.downloadSpeedBoost.rawValue)
    public var downloadSpeedBoost: String
    
    @UserDefault(key: Keys.rememberLastFolder.rawValue)
    public var rememberLastFolder: Bool
    
    // Disabled while Telegram is migrating to Glass
    // @UserDefault(key: Keys.bottomTabStyle.rawValue)
    public var bottomTabStyle: String {
        set {}
        get {
            return BottomTabStyleValues.ios.rawValue
        }
    }
    
    public var lastAccountFolders = UserDefaultsBackedDictionary<String, Int32>(userDefaultsKey: Keys.lastAccountFolders.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.localDNSForProxyHost.rawValue)
    public var localDNSForProxyHost: Bool
    
    @UserDefault(key: Keys.sendLargePhotos.rawValue)
    public var sendLargePhotos: Bool
    
    @UserDefault(key: Keys.outgoingPhotoQuality.rawValue)
    public var outgoingPhotoQuality: Int32

    @UserDefault(key: Keys.hideStories.rawValue)
    public var hideStories: Bool

    @UserDefault(key: Keys.disableAllAds.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var disableAllAds: Bool

    @UserDefault(key: Keys.antiRevoke.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var antiRevoke: Bool


    @UserDefault(key: Keys.antiAutoDelete.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var antiAutoDelete: Bool

    @UserDefault(key: Keys.antiSelfDestruct.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var antiSelfDestruct: Bool

    @UserDefault(key: Keys.antiScreenshotNotification.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var antiScreenshotNotification: Bool

    @UserDefault(key: Keys.allowSavingProtectedContent.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var allowSavingProtectedContent: Bool

    @UserDefault(key: Keys.allowDownloadingStories.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var allowDownloadingStories: Bool

    // MARK: Ghost Mode — each switch suppresses one outgoing signal. They are read on the network
    // path in TelegramCore (see RGGhostMode), never cached, so a change takes effect immediately.

    /// Stop pushing read receipts: history reads, thread reads, and voice/video "played" marks.
    /// Explicit user actions ("mark all as read", "read all mentions") are deliberately unaffected.
    @UserDefault(key: Keys.ghostDontReadMessages.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var ghostDontReadMessages: Bool

    /// Stop reporting story views. Sending a reaction or reply still marks the story seen server-side.
    @UserDefault(key: Keys.ghostDontReadStories.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var ghostDontReadStories: Bool

    /// Never report an online presence. Sending a message still puts you online — that is server-side.
    @UserDefault(key: Keys.ghostDontSendOnline.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var ghostDontSendOnline: Bool

    /// Stop sending input activities: typing, recording, choosing a sticker, upload progress.
    @UserDefault(key: Keys.ghostDontSendTyping.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var ghostDontSendTyping: Bool

    // MARK: Regram — pangu spacing for outgoing text.
    @UserDefault(key: Keys.panguSpacing.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var panguSpacing: Bool
















    @UserDefault(key: Keys.warnOnStoriesOpen.rawValue)
    public var warnOnStoriesOpen: Bool
    
    @UserDefault(key: Keys.storyStealthMode.rawValue)
    public var storyStealthMode: Bool
    
    @UserDefault(key: Keys.canUseStealthMode.rawValue)
    public var canUseStealthMode: Bool    
    
    @UserDefault(key: Keys.disableSwipeToRecordStory.rawValue)
    public var disableSwipeToRecordStory: Bool   
    
    @UserDefault(key: Keys.quickTranslateButton.rawValue)
    public var quickTranslateButton: Bool
    
    public var outgoingLanguageTranslation = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.outgoingLanguageTranslation.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.hideReactions.rawValue)
    public var hideReactions: Bool

    // @available(*, deprecated, message: "Use showRepostToStoryV2 instead")
    @UserDefault(key: Keys.showRepostToStory.rawValue)
    public var showRepostToStory: Bool

    @UserDefault(key: Keys.showRepostToStoryV2.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var showRepostToStoryV2: Bool

    @UserDefault(key: Keys.contextShowRestrict.rawValue)
    public var contextShowRestrict: Bool

    /*@UserDefault(key: Keys.contextShowBan.rawValue)
    public var contextShowBan: Bool*/

    @UserDefault(key: Keys.contextShowSelectFromUser.rawValue)
    public var contextShowSelectFromUser: Bool

    @UserDefault(key: Keys.contextShowSaveToCloud.rawValue)
    public var contextShowSaveToCloud: Bool

    @UserDefault(key: Keys.contextShowHideForwardName.rawValue)
    public var contextShowHideForwardName: Bool

    @UserDefault(key: Keys.contextShowReport.rawValue)
    public var contextShowReport: Bool

    @UserDefault(key: Keys.contextShowReply.rawValue)
    public var contextShowReply: Bool

    @UserDefault(key: Keys.contextShowPin.rawValue)
    public var contextShowPin: Bool

    @UserDefault(key: Keys.contextShowSaveMedia.rawValue)
    public var contextShowSaveMedia: Bool

    @UserDefault(key: Keys.contextShowMessageReplies.rawValue)
    public var contextShowMessageReplies: Bool
    
    @UserDefault(key: Keys.contextShowJson.rawValue)
    public var contextShowJson: Bool

    // MARK: Regram
    @UserDefault(key: Keys.contextShowRepeatForward.rawValue)
    public var contextShowRepeatForward: Bool

    @UserDefault(key: Keys.contextShowRepeatCopy.rawValue)
    public var contextShowRepeatCopy: Bool

    @UserDefault(key: Keys.profileDefaultTabGroupsInCommon.rawValue)
    public var profileDefaultTabGroupsInCommon: Bool

    /// Long-pressing an avatar to mention inserts the display name carrying a `tg://user?id=` link
    /// instead of a bare `@username`. Off by default: upstream's behaviour is what most people expect,
    /// and the link form is deliberate opt-in.
    @UserDefault(key: Keys.mentionAsUserIdLink.rawValue)
    public var mentionAsUserIdLink: Bool

    // MARK: Regram — local Premium. Off by default; enabled from the Regram Pro screen. When on, the
    // signed-in accounts read back as Premium inside the app so the client-side gates open. Nothing
    // is sent to Telegram and nothing is written to the database — see `rgIsLocalPremiumPeerId` in
    // TelegramCore. Features the server enforces still need a real subscription.
    @UserDefault(key: Keys.localPremium.rawValue)
    public var localPremium: Bool

    /// Emoji status picked while local Premium is on, keyed by account peer id. The server drops the
    /// status for a non-Premium account and pushes the empty one back, so it is kept here and
    /// re-applied when the peer is read. Values are JSON-encoded `PeerEmojiStatus`; written from the
    /// main queue and read from the Postbox queue, hence `threadSafe`.
    public var localPremiumEmojiStatus = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.localPremiumEmojiStatus.rawValue, threadSafe: true)

    // MARK: Regram — NSFW section. Off by default; enabled from the Regram Pro screen. When on, a
    // disclosure row appears in the main settings list (between My Profile and Proxy) that opens an
    // in-app web section.
    @UserDefault(key: Keys.nsfwEnabled.rawValue)
    public var nsfwEnabled: Bool

    /// Set once the user has confirmed they are of age on first entry, so the 18+ gate is not shown
    /// on every visit.
    @UserDefault(key: Keys.nsfwAgeConfirmed.rawValue)
    public var nsfwAgeConfirmed: Bool

    // MARK: Regram — disable previews for sent links. Off by default; enabled from Regram Pro.
    // The composer preview remains available, but outgoing messages carry Telegram's
    // `.disableLinkPreviews` attribute so the server does not attach a webpage preview.
    @UserDefault(key: Keys.disableLinkPreview.rawValue)
    public var disableLinkPreview: Bool

    /// Raw stored order of the Regram-managed message-menu items. Prefer `contextMenuOrder`, which
    /// repairs it; this is the unfiltered backing store and is only written by the reorder screen.
    @UserDefault(key: Keys.contextMenuOrder.rawValue)
    public var contextMenuOrderRaw: [String]

    /// The managed message-menu items in the order the user arranged them.
    ///
    /// Always a complete, duplicate-free permutation of `RGContextMenuItemId.allCases`, whatever is
    /// on disk: unknown ids (a setting removed in a later build) are dropped and missing ones (a
    /// setting added in a later build) are appended in canonical order. Without that repair an
    /// upgrade would silently lose the new item from the menu entirely, since the menu is emitted by
    /// walking this list.
    public var contextMenuOrder: [RGContextMenuItemId] {
        get {
            var seen = Set<RGContextMenuItemId>()
            var result: [RGContextMenuItemId] = []
            for rawValue in self.contextMenuOrderRaw {
                guard let id = RGContextMenuItemId(rawValue: rawValue), !seen.contains(id) else {
                    continue
                }
                seen.insert(id)
                result.append(id)
            }
            for id in RGContextMenuItemId.allCases where !seen.contains(id) {
                result.append(id)
            }
            return result
        }
        set {
            self.contextMenuOrderRaw = newValue.map { $0.rawValue }
        }
    }

    /// Whether `id` is shown in the main message menu. Off means it is still reachable, but from the
    /// "Regram" submenu — nothing is ever removed outright.
    public func contextMenuItemIsEnabled(_ id: RGContextMenuItemId) -> Bool {
        switch id {
        case .repeatForward: return self.contextShowRepeatForward
        case .repeatCopy: return self.contextShowRepeatCopy
        case .forwardNoQuote: return self.contextShowHideForwardName
        case .saveToCloud: return self.contextShowSaveToCloud
        case .selectFromUser: return self.contextShowSelectFromUser
        case .restrict: return self.contextShowRestrict
        case .report: return self.contextShowReport
        case .reply: return self.contextShowReply
        case .pin: return self.contextShowPin
        case .saveMedia: return self.contextShowSaveMedia
        case .messageReplies: return self.contextShowMessageReplies
        case .json: return self.contextShowJson
        }
    }

    public func setContextMenuItemIsEnabled(_ id: RGContextMenuItemId, _ value: Bool) {
        switch id {
        case .repeatForward: self.contextShowRepeatForward = value
        case .repeatCopy: self.contextShowRepeatCopy = value
        case .forwardNoQuote: self.contextShowHideForwardName = value
        case .saveToCloud: self.contextShowSaveToCloud = value
        case .selectFromUser: self.contextShowSelectFromUser = value
        case .restrict: self.contextShowRestrict = value
        case .report: self.contextShowReport = value
        case .reply: self.contextShowReply = value
        case .pin: self.contextShowPin = value
        case .saveMedia: self.contextShowSaveMedia = value
        case .messageReplies: self.contextShowMessageReplies = value
        case .json: self.contextShowJson = value
        }
    }
    
    @UserDefault(key: Keys.disableScrollToNextChannel.rawValue)
    public var disableScrollToNextChannel: Bool

    @UserDefault(key: Keys.disableScrollToNextTopic.rawValue)
    public var disableScrollToNextTopic: Bool

    @UserDefault(key: Keys.disableChatSwipeOptions.rawValue)
    public var disableChatSwipeOptions: Bool

    @UserDefault(key: Keys.disableDeleteChatSwipeOption.rawValue)
    public var disableDeleteChatSwipeOption: Bool

    @UserDefault(key: Keys.disableGalleryCamera.rawValue)
    public var disableGalleryCamera: Bool

    @UserDefault(key: Keys.disableGalleryCameraPreview.rawValue)
    public var disableGalleryCameraPreview: Bool

    @UserDefault(key: Keys.disableSendAsButton.rawValue)
    public var disableSendAsButton: Bool

    @UserDefault(key: Keys.disableSnapDeletionEffect.rawValue)
    public var disableSnapDeletionEffect: Bool
    
    @UserDefault(key: Keys.stickerSize.rawValue)
    public var stickerSize: Int32
    
    @UserDefault(key: Keys.stickerTimestamp.rawValue)
    public var stickerTimestamp: Bool    

    @UserDefault(key: Keys.hideRecordingButton.rawValue)
    public var hideRecordingButton: Bool
    
    @UserDefault(key: Keys.hideTabBar.rawValue)
    public var hideTabBar: Bool

    @UserDefault(key: Keys.showProfileId.rawValue)
    public var showProfileId: Bool
    
    @UserDefault(key: Keys.showDC.rawValue)
    public var showDC: Bool
    
    @UserDefault(key: Keys.showCreationDate.rawValue)
    public var showCreationDate: Bool

    @UserDefault(key: Keys.showRegDate.rawValue)
    public var showRegDate: Bool

    public var regDateCache = UserDefaultsBackedDictionary<String, Data>(userDefaultsKey: Keys.regDateCache.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.compactChatList.rawValue)
    public var compactChatList: Bool

    @UserDefault(key: Keys.chatListLines.rawValue)
    public var chatListLines: String

    @UserDefault(key: Keys.compactFolderNames.rawValue)
    public var compactFolderNames: Bool
    
    @UserDefault(key: Keys.allChatsTitleLengthOverride.rawValue)
    public var allChatsTitleLengthOverride: String
//    
//    @UserDefault(key: Keys.allChatsFolderPositionOverride.rawValue)
//    public var allChatsFolderPositionOverride: String
    @UserDefault(key: Keys.allChatsHidden.rawValue)
    public var allChatsHidden: Bool

    @UserDefault(key: Keys.defaultEmojisFirst.rawValue)
    public var defaultEmojisFirst: Bool
    
    @UserDefault(key: Keys.messageDoubleTapActionOutgoing.rawValue)
    public var messageDoubleTapActionOutgoing: String
    
    @UserDefault(key: Keys.wideChannelPosts.rawValue)
    public var wideChannelPosts: Bool

    @UserDefault(key: Keys.forceEmojiTab.rawValue)
    public var forceEmojiTab: Bool
    
    @UserDefault(key: Keys.forceBuiltInMic.rawValue)
    public var forceBuiltInMic: Bool
    
    @UserDefault(key: Keys.secondsInMessages.rawValue)
    public var secondsInMessages: Bool
    
    @UserDefault(key: Keys.hideChannelBottomButton.rawValue)
    public var hideChannelBottomButton: Bool

    @UserDefault(key: Keys.forceSystemSharing.rawValue)
    public var forceSystemSharing: Bool

    @UserDefault(key: Keys.confirmCalls.rawValue)
    public var confirmCalls: Bool
    
    @UserDefault(key: Keys.videoPIPSwipeDirection.rawValue)
    public var videoPIPSwipeDirection: String

    @UserDefault(key: Keys.legacyNotificationsFix.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var legacyNotificationsFix: Bool
    
    @UserDefault(key: Keys.status.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var status: Int64

    // Mirrors RGStatus.status. Defaults to Pro so gates read as unlocked before the shared-data
    // subscription in SharedAccountContext delivers its first value.
    public var ephemeralStatus: Int64 = 2
    
    @UserDefault(key: Keys.messageFilterKeywords.rawValue)
    public var messageFilterKeywords: [String]

    // MARK: Regram — message filter v2. JSON-encoded `[RGMessageFilterRule]`; see MessageFilter.swift.
    @UserDefault(key: Keys.messageFilterRules.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var messageFilterRulesJSON: String

    /// Posted whenever the message-filter rules or the hidden-sender list change. The chat history
    /// is rebuilt from a signal chain that only reacts to Postbox updates, so without an explicit
    /// notification a newly added rule would not take effect until some unrelated update happened
    /// to arrive.
    public static let contentFiltersDidChangeNotification = Notification.Name("SGSimpleSettings.contentFiltersDidChange")

    private func notifyContentFiltersChanged() {
        self.contentFilterCacheLock.lock()
        self.cachedMessageFilterRules = nil
        self.cachedBlockedPeerIds = nil
        self.cachedMessageFilterDisabledPeerIds = nil
        self.contentFilterGenerationValue += 1
        self.contentFilterCacheLock.unlock()
        NotificationCenter.default.post(name: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil)
    }

    private var contentFilterGenerationValue: Int = 0

    /// Bumped on every rule / hidden-sender change. Consumers that memoise a per-message verdict key
    /// their table on this, so a rule edit discards it wholesale instead of needing to know which
    /// messages a rule could have affected.
    public var contentFilterGeneration: Int {
        self.contentFilterCacheLock.lock()
        defer { self.contentFilterCacheLock.unlock() }
        return self.contentFilterGenerationValue
    }

    /// The decoded rules and hidden-sender set are read once per chat-history rebuild, which happens
    /// on every scroll-driven window change, so the JSON decode is memoised. Only the setters below
    /// write the backing keys, and each of them invalidates through `notifyContentFiltersChanged`.
    private let contentFilterCacheLock = NSLock()
    private var cachedMessageFilterRules: [RGMessageFilterRule]?
    private var cachedBlockedPeerIds: Set<Int64>?
    private var cachedMessageFilterDisabledPeerIds: Set<Int64>?

    /// Decoded view over `messageFilterRulesJSON`.
    public var messageFilterRules: [RGMessageFilterRule] {
        get {
            self.contentFilterCacheLock.lock()
            defer { self.contentFilterCacheLock.unlock() }
            if let cached = self.cachedMessageFilterRules {
                return cached
            }
            let decoded = RGMessageFilter.decode(self.messageFilterRulesJSON)
            self.cachedMessageFilterRules = decoded
            return decoded
        }
        set {
            self.messageFilterRulesJSON = RGMessageFilter.encode(newValue)
            self.notifyContentFiltersChanged()
        }
    }

    // MARK: Regram — client-side blocked peers. Stored as decimal strings because `@UserDefault`
    // reads integer arrays back through `stringArray(forKey:)`-style accessors only.
    @UserDefault(key: Keys.blockedPeerIds.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var blockedPeerIdsRaw: [String]

    public var blockedPeerIds: Set<Int64> {
        get {
            self.contentFilterCacheLock.lock()
            defer { self.contentFilterCacheLock.unlock() }
            if let cached = self.cachedBlockedPeerIds {
                return cached
            }
            let decoded = Set(self.blockedPeerIdsRaw.compactMap { Int64($0) })
            self.cachedBlockedPeerIds = decoded
            return decoded
        }
        set {
            self.blockedPeerIdsRaw = newValue.map { String($0) }
            self.notifyContentFiltersChanged()
        }
    }

    // MARK: Regram — chats the keyword filter is switched off in, toggled from the chat's own
    // profile. Exceptions rather than opt-ins, so "on everywhere" costs no stored state.
    @UserDefault(key: Keys.messageFilterDisabledPeerIds.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var messageFilterDisabledPeerIdsRaw: [String]

    public var messageFilterDisabledPeerIds: Set<Int64> {
        get {
            self.contentFilterCacheLock.lock()
            defer { self.contentFilterCacheLock.unlock() }
            if let cached = self.cachedMessageFilterDisabledPeerIds {
                return cached
            }
            let decoded = Set(self.messageFilterDisabledPeerIdsRaw.compactMap { Int64($0) })
            self.cachedMessageFilterDisabledPeerIds = decoded
            return decoded
        }
        set {
            self.messageFilterDisabledPeerIdsRaw = newValue.map { String($0) }
            self.notifyContentFiltersChanged()
        }
    }

    public func isMessageFilterEnabled(forPeer peerId: Int64) -> Bool {
        if self.messageFilterDisabledPeerIdsRaw.isEmpty {
            return true
        }
        return !self.messageFilterDisabledPeerIdsRaw.contains(String(peerId))
    }

    public func setMessageFilterEnabled(_ enabled: Bool, forPeer peerId: Int64) {
        var ids = self.messageFilterDisabledPeerIds
        if enabled {
            ids.remove(peerId)
        } else {
            ids.insert(peerId)
        }
        self.messageFilterDisabledPeerIds = ids
    }

    public func isPeerBlocked(_ peerId: Int64) -> Bool {
        if self.blockedPeerIdsRaw.isEmpty {
            return false
        }
        return self.blockedPeerIdsRaw.contains(String(peerId))
    }

    public func setPeerBlocked(_ peerId: Int64, blocked: Bool) {
        var ids = self.blockedPeerIds
        if blocked {
            ids.insert(peerId)
        } else {
            ids.remove(peerId)
        }
        self.blockedPeerIds = ids
    }

    /// Appends a rule, ignoring exact duplicates (same pattern, mode and scope).
    @discardableResult
    public func addMessageFilterRule(_ rule: RGMessageFilterRule) -> Bool {
        var rules = self.messageFilterRules
        if rules.contains(where: { $0.pattern == rule.pattern && $0.isRegex == rule.isRegex && Set($0.peerIds) == Set(rule.peerIds) }) {
            return false
        }
        rules.append(rule)
        self.messageFilterRules = rules
        return true
    }


    @UserDefault(key: Keys.inputToolbar.rawValue)
    public var inputToolbar: Bool

    @UserDefault(key: Keys.sendWithReturnKey.rawValue)
    public var sendWithReturnKey: Bool
    
    @UserDefault(key: Keys.pinnedMessageNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var pinnedMessageNotifications: String
    
    @UserDefault(key: Keys.mentionsAndRepliesNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var mentionsAndRepliesNotifications: String
    
    @UserDefault(key: Keys.primaryUserId.rawValue)
    public var primaryUserId: String

    @UserDefault(key: Keys.dismissedSGSuggestions.rawValue)
    public var dismissedSGSuggestions: [String]

    @UserDefault(key: Keys.duckyAppIconAvailable.rawValue)
    public var duckyAppIconAvailable: Bool

    @UserDefault(key: Keys.transcriptionBackend.rawValue)
    public var transcriptionBackend: String

    @UserDefault(key: Keys.translationBackend.rawValue)
    public var translationBackend: String

    @UserDefault(key: Keys.customAppBadge.rawValue)
    public var customAppBadge: String

    @UserDefault(key: Keys.canUseNY.rawValue)
    public var canUseNY: Bool

    @UserDefault(key: Keys.nyStyle.rawValue)
    public var nyStyle: String

    @UserDefault(key: Keys.wideTabBar.rawValue)
    public var wideTabBar: Bool
    
    @UserDefault(key: Keys.tabBarSearchEnabled.rawValue)
    public var tabBarSearchEnabled: Bool
}

extension RGSimpleSettings {
    public var isStealthModeEnabled: Bool {
        return storyStealthMode && canUseStealthMode
    }
    
    public static func makeOutgoingLanguageTranslationKey(accountId: Int64, peerId: Int64) -> String {
        return "\(accountId):\(peerId)"
    }
}

extension RGSimpleSettings {
    public var translationBackendEnum: RGSimpleSettings.TranslationBackend {
        return TranslationBackend(rawValue: translationBackend) ?? .default
    }

    /// Backends served by a third-party web endpoint rather than by Telegram or by the OS. Those
    /// translate a plain string, so messages have to be routed through the via-text path.
    public var translationBackendIsExternal: Bool {
        switch translationBackendEnum {
        case .gtranslate, .google:
            return true
        case .default, .system:
            return false
        }
    }

    public var transcriptionBackendEnum: RGSimpleSettings.TranscriptionBackend {
        return TranscriptionBackend(rawValue: transcriptionBackend) ?? .default
    }
}

extension RGSimpleSettings {
    public var isNYEnabled: Bool {
        return canUseNY && NYStyle(rawValue: nyStyle) != .default
    }
}

public func getRGDownloadPartSize(_ default: Int64, fileSize: Int64?) -> Int64 {
    let currentDownloadSetting = RGSimpleSettings.shared.downloadSpeedBoost
    // Increasing chunk size for small files make it worse in terms of overall download performance
    let smallFileSizeThreshold = 1 * 1024 * 1024 // 1 MB
    switch (currentDownloadSetting) {
        case RGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 512 * 1024
        case RGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 1024 * 1024
        default:
            return `default`
    }
}

public func getRGMaxPendingParts(_ default: Int) -> Int {
    let currentDownloadSetting = RGSimpleSettings.shared.downloadSpeedBoost
    switch (currentDownloadSetting) {
        case RGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            return 8
        case RGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            return 12
        default:
            return `default`
    }
}

public func rgUseShortAllChatsTitle(_ default: Bool) -> Bool {
    let currentOverride = RGSimpleSettings.shared.allChatsTitleLengthOverride
    switch (currentOverride) {
        case RGSimpleSettings.AllChatsTitleLengthOverride.short.rawValue:
            return true
        case RGSimpleSettings.AllChatsTitleLengthOverride.long.rawValue:
            return false
        default:
            return `default`
    }
}

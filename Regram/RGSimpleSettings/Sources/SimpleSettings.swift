import Foundation
import RGAppGroupIdentifier
import RGLogging

let APP_GROUP_USER_DEFAULTS = rgSharedUserDefaults()

public class RGSimpleSettings {
    
    public static let shared = RGSimpleSettings()
    
    public var bottomBarSettings: RGBottomBarSettings {
        get { RGBottomBarSettings.load() }
        set {
            newValue.save()
            // Keep legacy backup keys readable by older Regram builds.
            self.hideTabBar = !newValue.isBottomBarVisible
            self.showTabNames = newValue.showLabels
            DispatchQueue.main.async { NotificationCenter.default.post(name: RGTabBarLayoutPolicy.settingsChanged, object: nil) }
        }
    }

    private init() {
        setDefaultValues()
        migrate()
        preCacheValues()
    }
    
    private func setDefaultValues() {
        UserDefaults.standard.register(defaults: RGSimpleSettings.defaultValues)
        // Just in case group defaults will be nil
        UserDefaults.standard.register(defaults: RGSimpleSettings.groupDefaultValues)
        if let groupUserDefaults = APP_GROUP_USER_DEFAULTS {
            groupUserDefaults.register(defaults: RGSimpleSettings.groupDefaultValues)
        }
    }
    
    private func migrate() {
        // MARK: Regram — Google/GTranslate now share one backend, including imported old settings.
        if self.translationBackend == "gtranslate" { self.translationBackend = TranslationBackend.google.rawValue }
        // MARK: Regram — remove the high-load tier while preserving an enabled download boost.
        if self.downloadSpeedBoost == "maximum" { self.downloadSpeedBoost = DownloadSpeedBoostValues.enabled.rawValue }
        // MARK: Regram — persist the supported mode when upgrading an old three-line setting.
        if storedChatListLines != chatListLines { self.chatListLines = chatListLines }
        UserDefaults.standard.removeObject(forKey: "nsfwEnabled")
        UserDefaults.standard.removeObject(forKey: "nsfwAgeConfirmed")
        let showRepostToStoryMigrationKey = "migrated_\(Keys.showRepostToStory.rawValue)"
        if let groupUserDefaults = APP_GROUP_USER_DEFAULTS {
            if !groupUserDefaults.bool(forKey: showRepostToStoryMigrationKey) {
                self.showRepostToStoryV2 = self.showRepostToStory
                groupUserDefaults.set(true, forKey: showRepostToStoryMigrationKey)
                RGLogger.shared.log("RGSimpleSettings", "Migrated showRepostToStory. \(self.showRepostToStory) -> \(self.showRepostToStoryV2)")
            }
        } else {
            RGLogger.shared.log("RGSimpleSettings", "Unable to migrate showRepostToStory. Shared UserDefaults are not available.")
        }

        // MARK: Regram — message filter v2. Plain keywords become all-chat substring rules.
        let messageFilterRulesMigrationKey = "migrated_\(Keys.messageFilterRules.rawValue)"
        if !UserDefaults.standard.bool(forKey: messageFilterRulesMigrationKey) {
            let legacyKeywords = self.messageFilterKeywords
            if !legacyKeywords.isEmpty, self.messageFilterRules.isEmpty {
                self.messageFilterRules = legacyKeywords.map { RGMessageFilterRule(pattern: $0) }
                RGLogger.shared.log("RGSimpleSettings", "Migrated \(legacyKeywords.count) messageFilterKeywords -> messageFilterRules")
            }
            UserDefaults.standard.set(true, forKey: messageFilterRulesMigrationKey)
        }

        // MARK: Regram — double tap v2. The old switch only chose between the reaction and editing
        // your own messages; editable messages keep that choice and every other one reacts.
        let messageDoubleTapMigrationKey = "migrated_\(Keys.messageDoubleTapAction.rawValue)"
        if !UserDefaults.standard.bool(forKey: messageDoubleTapMigrationKey) {
            switch self.messageDoubleTapActionOutgoing {
            case MessageDoubleTapAction.edit.rawValue:
                self.messageDoubleTapAction = MessageDoubleTapActionV2.edit.rawValue
                self.messageDoubleTapActionWithoutEditPermission = MessageDoubleTapActionV2.sendReaction.rawValue
            case MessageDoubleTapAction.none.rawValue:
                self.messageDoubleTapAction = MessageDoubleTapActionV2.disabled.rawValue
                self.messageDoubleTapActionWithoutEditPermission = MessageDoubleTapActionV2.sendReaction.rawValue
            default:
                break
            }
            UserDefaults.standard.set(true, forKey: messageDoubleTapMigrationKey)
        }

        let chatListLinesMigrationKey = "migrated_\(Keys.chatListLines.rawValue)"
        if !UserDefaults.standard.bool(forKey: chatListLinesMigrationKey) {
            let legacyCompactMessagePreviewKey = "compactMessagePreview"
            if UserDefaults.standard.object(forKey: legacyCompactMessagePreviewKey) != nil {
                if UserDefaults.standard.bool(forKey: legacyCompactMessagePreviewKey) {
                    self.chatListLines = ChatListLines.one.rawValue
                }
                UserDefaults.standard.removeObject(forKey: legacyCompactMessagePreviewKey)
                RGLogger.shared.log("RGSimpleSettings", "Migrated compactMessagePreview -> chatListLines. \(self.chatListLines)")
            }
            UserDefaults.standard.set(true, forKey: chatListLinesMigrationKey)
        }

        // MARK: Regram — split the old single typeface choice without replacing saved script settings.
        let fontScriptsMigrationKey = "migrated_fontScripts"
        if !UserDefaults.standard.bool(forKey: fontScriptsMigrationKey) {
            let stored = Bundle.main.bundleIdentifier.flatMap {
                UserDefaults.standard.persistentDomain(forName: $0)?[Keys.fontChineseFamily.rawValue]
            }
            if stored == nil {
                let choices = RGFontConfiguration.migratedChoices(legacyFamily: self.fontFamily)
                self.fontFamily = choices.latin.rawValue
                self.fontChineseFamily = choices.chinese.rawValue
            }
            UserDefaults.standard.set(true, forKey: fontScriptsMigrationKey)
        }

        // MARK: Regram — retain the old wide-bar choice without retaining its obsolete search math.
        let tabBarWidthMigrationKey = "migrated_\(Keys.tabBarWidthPercent.rawValue)"
        if !UserDefaults.standard.bool(forKey: tabBarWidthMigrationKey) {
            let stored = Bundle.main.bundleIdentifier.flatMap {
                UserDefaults.standard.persistentDomain(forName: $0)?[Keys.tabBarWidthPercent.rawValue]
            }
            if stored == nil {
                self.tabBarWidthPercent = RGTabBarLayoutPolicy.migratedPercent(legacyWide: self.wideTabBar)
            }
            UserDefaults.standard.set(true, forKey: tabBarWidthMigrationKey)
        }
    }
    
    private func preCacheValues() {
        // let dispatchGroup = DispatchGroup()

        let tasks = [
//            { let _ = self.allChatsFolderPositionOverride },
            { let _ = self.tabBarWidthPercent },
            { let _ = self.allChatsHidden },
            { let _ = self.hideTabBar },
            { let _ = self.compactChatList },
            { let _ = self.chatListLines },
            { let _ = self.compactFolderNames },
            { let _ = self.disableSwipeToRecordStory },
            { let _ = self.rememberLastFolder },
            { let _ = self.quickTranslateButton },
            { let _ = self.stickerSize },
            { let _ = self.stickerTimestamp },
            { let _ = self.recentStickerLimit },
            { let _ = self.hideReactions },
            { let _ = self.disableGalleryCamera },
            { let _ = self.disableSendAsButton },
            { let _ = self.disableSnapDeletionEffect },
            { let _ = self.startTelescopeWithRearCam },
            { let _ = self.hideRecordingButton },
            { let _ = self.inputToolbar },
            { let _ = self.dismissedRGSuggestions },
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
        if let groupUserDefaults = APP_GROUP_USER_DEFAULTS {
            groupUserDefaults.synchronize()
        }
    }
    
    public enum Keys: String, CaseIterable {
        case hidePhoneInSettings
        case showTabNames
        case fontFamily
        case fontImportedLatin
        case fontImportedChinese
        case fontAssetsRevision
        case fontChineseFamily
        case fontApplyToMessages
        case fontApplyToInterface
        case startTelescopeWithRearCam
        case accountColorsSaturation
        case uploadSpeedBoost
        case downloadSpeedBoost
        case mediaLoadingExperiment
        case showMediaMetadata // MARK: Regram — "Media Info" in the photo/video viewer menu
        case defaultVideoQuality // MARK: Regram
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
        case contextShowEditHistory
        case contextMenuOrder
        case contextMenuDisabledItems
        case profileDefaultTabGroupsInCommon
        case mentionAsUserIdLink
        case localPremium
        case localPremiumEmojiStatus
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
        case recentStickerLimit
        case defaultOutgoingFormatting
        case hideRecordingButton
        case hideTabBar
        case showDC
        case showCreationDate
        case showRegDate
        case regDateCache
        case compactChatList
        case hideChatListSeparators
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
        case messageFilterKeywords
        case messageFilterRules
        case blockedPeerIds
        case messageFilterDisabledPeerIds
        case antiRevokePeerIds
        case inputToolbar
        case pinnedMessageNotifications
        case mentionsAndRepliesNotifications
        case primaryUserId

        case dismissedRGSuggestions
        case transcriptionBackend
        case translationBackend
        case sttBaseURL
        case sttEndpoint
        case sttModel
        case sttLanguage
        case sttPrompt
        case fixLinkPreviews
        case linkPreviewXHost
        case linkPreviewInstagramHost
        case translationLLMAPIFormat
        case translationLLMBaseURL
        case translationLLMEndpoint
        case translationLLMModel
        case translationLLMPrompt
        case translationLLMUseContext
        case translationLLMTemperatureTenths
        case customAppBadge
        case canUseNY
        case nyStyle
        case wideTabBar
        case tabBarWidthPercent // MARK: Regram
        case tabBarSearchEnabled
        case hideStories
        case disableAllAds
        case antiRevoke
        case revokedMarkerStyle, revokedMarkerText, revokedMarkerColor // MARK: Regram
        case antiAutoDelete
        case antiSelfDestruct
        case antiScreenshotNotification
        case allowSavingProtectedContent
        case allowDownloadingStories
        // MARK: Ghost Mode — suppress outgoing presence/activity signals
        case ghostDontReadStories
        case ghostDontSendOnline
        case ghostDontSendTyping
        // MARK: Regram — insert a space between CJK and Latin/digits in outgoing text
        case panguSpacing
        case warnOnStoriesOpen
        case showProfileId
        case sendWithReturnKey
        case chatPreferences
        case filterNotifications
        // MARK: Regram — pins beyond the account's server limit, and prior versions of edited messages
        case unlimitedPinnedChats
        case saveEditHistory
        case recentChatsEnabled
        // MARK: Regram — offer a chat folder picker after joining a group or channel
        case chooseFolderAfterJoining
        case messageDoubleTapAction
        case messageDoubleTapActionWithoutEditPermission
        case showMessageId
        case automaticallyRevealSpoilers // MARK: Regram
        case showForwardedMessageDate
    }
    
    public enum DownloadSpeedBoostValues: String, CaseIterable {
        case none
        case enabled = "medium"
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
        case two = "2"
        case one = "1"

        public static let defaultValue: ChatListLines = .two
    }
    
    public enum MessageDoubleTapAction: String, CaseIterable {
        case `default`
        case none
        case edit
    }

    // MARK: Regram — what a double tap on a message does. `messageDoubleTapAction` applies to every
    // message; `messageDoubleTapActionWithoutEditPermission` overrides it for messages this account
    // cannot edit, unless it is `sameAsUnified`. Raw values are persisted.
    public enum MessageDoubleTapActionV2: String, CaseIterable {
        case disabled
        case sendReaction
        case showReactions
        case reply
        case repeatMessage
        case repeatWithoutQuote
        case translate
        case edit
    }

    public static let messageDoubleTapSameAsUnified = "sameAsUnified"
    
    public enum TranscriptionBackend: String, CaseIterable {
        case `default`
        case apple
        case openAICompatible
    }

    public enum TranslationBackend: String, CaseIterable {
        case `default`
        case google
        case googleCN
        case microsoft
        case yandex
        case transmart
        case llm
        case system
        // Make sure to update TranslationConfiguration
    }

    public enum DefaultOutgoingFormat: String, CaseIterable {
        case none
        case bold
        case italic
        case underline
        case strikethrough
        case spoiler
    }

    public static let recentStickerLimitOptions: [Int32] = [20, 30, 40, 50, 60, 80, 100, 120, 150, 200]
        
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
        Keys.fontFamily.rawValue: RGFontFamily.system.rawValue,
        Keys.fontImportedLatin.rawValue: "",
        Keys.fontImportedChinese.rawValue: "",
        Keys.fontAssetsRevision.rawValue: 0,
        Keys.fontChineseFamily.rawValue: RGChineseFontFamily.system.rawValue,
        Keys.fontApplyToMessages.rawValue: true,
        Keys.fontApplyToInterface.rawValue: true,
        Keys.startTelescopeWithRearCam.rawValue: false,
        Keys.accountColorsSaturation.rawValue: 100,
        Keys.uploadSpeedBoost.rawValue: false,
        Keys.downloadSpeedBoost.rawValue: DownloadSpeedBoostValues.none.rawValue,
        Keys.mediaLoadingExperiment.rawValue: RGMediaLoadingPolicy.enabledByDefault,
        Keys.showMediaMetadata.rawValue: true,
        Keys.defaultVideoQuality.rawValue: RGVideoQualityPreference.automatic.rawValue,
        Keys.rememberLastFolder.rawValue: false,
        Keys.bottomTabStyle.rawValue: BottomTabStyleValues.telegram.rawValue,
        Keys.lastAccountFolders.rawValue: [:],
        Keys.localDNSForProxyHost.rawValue: false,
        Keys.sendLargePhotos.rawValue: false,
        Keys.outgoingPhotoQuality.rawValue: 100,
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
        Keys.contextShowEditHistory.rawValue: true,
        // MARK: Regram
        Keys.contextShowRepeatForward.rawValue: true,
        Keys.contextShowRepeatCopy.rawValue: true,
        Keys.contextMenuDisabledItems.rawValue: [String](),
        Keys.contextMenuOrder.rawValue: RGContextMenuItemId.allCases.map { $0.rawValue },
        Keys.profileDefaultTabGroupsInCommon.rawValue: false,
        Keys.mentionAsUserIdLink.rawValue: false,
        Keys.localPremium.rawValue: false,
        Keys.localPremiumEmojiStatus.rawValue: [:],
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
        Keys.recentStickerLimit.rawValue: 20,
        Keys.defaultOutgoingFormatting.rawValue: DefaultOutgoingFormat.none.rawValue,
        Keys.hideRecordingButton.rawValue: false,
        Keys.hideTabBar.rawValue: false,
        Keys.showDC.rawValue: false,
        Keys.showCreationDate.rawValue: true,
        Keys.showRegDate.rawValue: true,
        Keys.regDateCache.rawValue: [:],
        Keys.hideChatListSeparators.rawValue: false,
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
        Keys.messageFilterKeywords.rawValue: [],
        Keys.inputToolbar.rawValue: false,
        Keys.primaryUserId.rawValue: "",
        Keys.dismissedRGSuggestions.rawValue: [],
        Keys.transcriptionBackend.rawValue: TranscriptionBackend.default.rawValue,
        Keys.sttBaseURL.rawValue: "",
        Keys.sttEndpoint.rawValue: "",
        Keys.sttModel.rawValue: "",
        Keys.sttLanguage.rawValue: "",
        Keys.sttPrompt.rawValue: "",
        Keys.fixLinkPreviews.rawValue: false,
        Keys.linkPreviewXHost.rawValue: RGLinkPreviewRules.defaultXHost,
        Keys.linkPreviewInstagramHost.rawValue: RGLinkPreviewRules.defaultInstagramHost,
        Keys.translationLLMAPIFormat.rawValue: "openai",
        Keys.translationLLMBaseURL.rawValue: "",
        Keys.translationLLMEndpoint.rawValue: "",
        Keys.translationLLMModel.rawValue: "",
        Keys.translationLLMPrompt.rawValue: "Translate to @toLang:\n\n@text",
        Keys.translationLLMUseContext.rawValue: false,
        Keys.translationLLMTemperatureTenths.rawValue: Int32(2),
        Keys.translationBackend.rawValue: TranslationBackend.default.rawValue,
        Keys.customAppBadge.rawValue: RGAppBadgeNames.defaultName,
        Keys.canUseNY.rawValue: false,
        Keys.nyStyle.rawValue: NYStyle.default.rawValue,
        Keys.wideTabBar.rawValue: false,
        Keys.tabBarWidthPercent.rawValue: Int32(0),
        Keys.tabBarSearchEnabled.rawValue: true,
        Keys.hideStories.rawValue: false,
        Keys.disableAllAds.rawValue: false,
        Keys.antiRevoke.rawValue: false,
        Keys.revokedMarkerStyle.rawValue: "icon", Keys.revokedMarkerText.rawValue: "", Keys.revokedMarkerColor.rawValue: "",
        Keys.antiAutoDelete.rawValue: false,
        Keys.antiSelfDestruct.rawValue: false,
        Keys.antiScreenshotNotification.rawValue: false,
        Keys.allowSavingProtectedContent.rawValue: false,
        Keys.allowDownloadingStories.rawValue: false,
        Keys.warnOnStoriesOpen.rawValue: false,
        Keys.showProfileId.rawValue: true,
        Keys.sendWithReturnKey.rawValue: false,
        Keys.unlimitedPinnedChats.rawValue: true,
        Keys.saveEditHistory.rawValue: true,
        Keys.recentChatsEnabled.rawValue: true,
        Keys.chooseFolderAfterJoining.rawValue: false,
        Keys.messageDoubleTapAction.rawValue: MessageDoubleTapActionV2.sendReaction.rawValue,
        Keys.messageDoubleTapActionWithoutEditPermission.rawValue: RGSimpleSettings.messageDoubleTapSameAsUnified,
        Keys.showMessageId.rawValue: false,
        Keys.automaticallyRevealSpoilers.rawValue: false,
        Keys.showForwardedMessageDate.rawValue: false,
        Keys.chatPreferences.rawValue: "{}"
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.showRepostToStoryV2.rawValue: true,
        Keys.messageFilterRules.rawValue: "[]",
        Keys.blockedPeerIds.rawValue: [],
        Keys.messageFilterDisabledPeerIds.rawValue: [],
        Keys.antiRevokePeerIds.rawValue: [],
        // MARK: Ghost Mode — the app group suite, because the share/notification extensions run
        // TelegramCore too and must not leak a presence signal the main app is suppressing.
        Keys.ghostDontReadStories.rawValue: false,
        Keys.ghostDontSendOnline.rawValue: false,
        Keys.ghostDontSendTyping.rawValue: false,
        // MARK: Regram — pangu spacing.
        Keys.panguSpacing.rawValue: false,
        Keys.filterNotifications.rawValue: false,
    ]
    
    @UserDefault(key: Keys.hidePhoneInSettings.rawValue)
    public var hidePhoneInSettings: Bool
    
    public var fontConfiguration: RGFontConfiguration {
        return RGFontConfiguration(family: fontFamily, messages: fontApplyToMessages, interface: fontApplyToInterface, chineseFamily: fontChineseFamily, importedLatin: fontImportedLatin, importedChinese: fontImportedChinese, assetsRevision: fontAssetsRevision)
    }

    @UserDefault(key: Keys.fontImportedLatin.rawValue)
    public var fontImportedLatin: String {
        didSet { if fontImportedLatin != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.fontImportedChinese.rawValue)
    public var fontImportedChinese: String {
        didSet { if fontImportedChinese != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.fontAssetsRevision.rawValue)
    public var fontAssetsRevision: Int {
        didSet { if fontAssetsRevision != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.fontFamily.rawValue)
    public var fontFamily: String {
        didSet { if fontFamily != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.fontChineseFamily.rawValue)
    public var fontChineseFamily: String {
        didSet { if fontChineseFamily != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.fontApplyToMessages.rawValue)
    public var fontApplyToMessages: Bool {
        didSet { if fontApplyToMessages != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.fontApplyToInterface.rawValue)
    public var fontApplyToInterface: Bool {
        didSet { if fontApplyToInterface != oldValue { NotificationCenter.default.post(name: RGFontConfiguration.settingsChanged, object: nil) } }
    }

    @UserDefault(key: Keys.showTabNames.rawValue)
    public var showTabNames: Bool {
        didSet {
            if showTabNames != oldValue { NotificationCenter.default.post(name: RGTabBarLayoutPolicy.settingsChanged, object: nil) }
        }
    }
    
    @UserDefault(key: Keys.startTelescopeWithRearCam.rawValue)
    public var startTelescopeWithRearCam: Bool
    
    @UserDefault(key: Keys.accountColorsSaturation.rawValue)
    public var accountColorsSaturation: Int32
    
    @UserDefault(key: Keys.uploadSpeedBoost.rawValue)
    public var uploadSpeedBoost: Bool
    
    @UserDefault(key: Keys.downloadSpeedBoost.rawValue)
    public var downloadSpeedBoost: String

    // MARK: Regram — reversible comparison with the original media loading behavior.
    @UserDefault(key: Keys.mediaLoadingExperiment.rawValue)
    public var mediaLoadingExperiment: Bool {
        didSet {
            NotificationCenter.default.post(name: RGMediaLoadingPolicy.settingsChanged, object: nil)
        }
    }

    // MARK: Regram — offer "Media Info" (resolution, codec, bitrate…) in the photo/video viewer menu.
    @UserDefault(key: Keys.showMediaMetadata.rawValue)
    public var showMediaMetadata: Bool

    @UserDefault(key: Keys.defaultVideoQuality.rawValue)
    public var defaultVideoQuality: String {
        didSet { NotificationCenter.default.post(name: RGVideoQualityPreference.settingsChanged, object: nil) }
    }
    
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
    
    // MARK: Regram — the DNS choices are mutually exclusive and shared with extensions.
    public var localDNSForProxyHost: Bool {
        get {
            let defaults = Bundle.main.bundlePath.hasSuffix(".appex") ? APP_GROUP_USER_DEFAULTS ?? UserDefaults.standard : UserDefaults.standard
            return defaults.bool(forKey: Keys.localDNSForProxyHost.rawValue) && !defaults.bool(forKey: "customDoHEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.localDNSForProxyHost.rawValue)
            APP_GROUP_USER_DEFAULTS?.set(newValue, forKey: Keys.localDNSForProxyHost.rawValue)
            if newValue {
                var policy = self.networkPolicy; policy.dohEnabled = false; policy.useSystemDNS = true; policy.save(to: UserDefaults.standard)
                if let shared = APP_GROUP_USER_DEFAULTS { policy.save(to: shared) }
            }
            NotificationCenter.default.post(name: RGNetworkPolicy.didChange, object: nil)
        }
    }
    
    @UserDefault(key: Keys.sendLargePhotos.rawValue)
    public var sendLargePhotos: Bool
    
    @UserDefault(key: Keys.outgoingPhotoQuality.rawValue)
    public var outgoingPhotoQuality: Int32

    @UserDefault(key: Keys.hideStories.rawValue)
    public var hideStories: Bool

    @UserDefault(key: Keys.disableAllAds.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var disableAllAds: Bool

    @UserDefault(key: Keys.antiRevoke.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var antiRevoke: Bool

    // MARK: Regram — visual marker preferences live in the main application only.
    @UserDefault(key: Keys.revokedMarkerStyle.rawValue) public var revokedMarkerStyle: String
    @UserDefault(key: Keys.revokedMarkerText.rawValue) public var revokedMarkerText: String
    @UserDefault(key: Keys.revokedMarkerColor.rawValue) public var revokedMarkerColor: String


    @UserDefault(key: Keys.antiAutoDelete.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var antiAutoDelete: Bool

    @UserDefault(key: Keys.antiSelfDestruct.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var antiSelfDestruct: Bool

    @UserDefault(key: Keys.antiScreenshotNotification.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var antiScreenshotNotification: Bool

    @UserDefault(key: Keys.allowSavingProtectedContent.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var allowSavingProtectedContent: Bool

    @UserDefault(key: Keys.allowDownloadingStories.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var allowDownloadingStories: Bool

    // MARK: Ghost Mode — each switch suppresses one outgoing signal. They are read on the network
    // path in TelegramCore (see RGGhostMode), never cached, so a change takes effect immediately.

    /// Stop reporting story views. Sending a reaction or reply still marks the story seen server-side.
    @UserDefault(key: Keys.ghostDontReadStories.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var ghostDontReadStories: Bool

    /// Never report an online presence. Sending a message still puts you online — that is server-side.
    @UserDefault(key: Keys.ghostDontSendOnline.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var ghostDontSendOnline: Bool

    /// Stop sending input activities: typing, recording, choosing a sticker, upload progress.
    @UserDefault(key: Keys.ghostDontSendTyping.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var ghostDontSendTyping: Bool

    // MARK: Regram — pangu spacing for outgoing text.
    @UserDefault(key: Keys.panguSpacing.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var panguSpacing: Bool

    @UserDefault(key: Keys.filterNotifications.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var filterNotifications: Bool
    public var canSharePreferencesWithExtensions: Bool { rgResolvedAppGroupIdentifier() != nil }

    @UserDefault(key: Keys.chatPreferences.rawValue)
    public var chatPreferencesJSON: String
    private let chatPreferencesLock = NSLock()
    private var cachedChatPreferencesJSON: String?
    private var cachedChatPreferences: [String: RGChatPreferences] = [:]
    private let temporaryReveal = RGTemporaryRevealState()

    public func temporarilyVisiblePeerIds(accountId: Int64) -> Set<Int64> {
        self.temporaryReveal.visiblePeerIds(accountId: accountId, now: ProcessInfo.processInfo.systemUptime)
    }
    public func temporarilyReveal(accountId: Int64, peerId: Int64, seconds: TimeInterval = 300) {
        guard seconds.isFinite else { return }
        let duration = max(1, min(300, seconds))
        let ticket = self.temporaryReveal.begin(accountId: accountId, peerId: peerId, seconds: duration, now: ProcessInfo.processInfo.systemUptime)
        self.notifyContentFiltersChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.temporaryReveal.end(accountId: accountId, peerId: peerId, ticket: ticket) else { return }
            self.notifyContentFiltersChanged()
        }
    }
    public func endTemporaryReveal(accountId: Int64, peerId: Int64) {
        if self.temporaryReveal.end(accountId: accountId, peerId: peerId) { self.notifyContentFiltersChanged() }
    }

    public var chatPreferencesSnapshot: [String: RGChatPreferences] {
        self.chatPreferencesLock.lock(); defer { self.chatPreferencesLock.unlock() }
        let json = self.chatPreferencesJSON
        if self.cachedChatPreferencesJSON != json {
            self.cachedChatPreferences = (try? JSONDecoder().decode([String: RGChatPreferences].self, from: Data(json.utf8))) ?? [:]
            self.cachedChatPreferencesJSON = json
        }
        return self.cachedChatPreferences
    }

    public func chatPreferences(accountId: Int64, peerId: Int64) -> RGChatPreferences {
        let values = self.chatPreferencesSnapshot
        return values[RGChatPreferences.key(accountId: accountId, peerId: peerId)] ?? RGChatPreferences()
    }

    public func setChatPreferences(_ value: RGChatPreferences, accountId: Int64, peerId: Int64) {
        var values = self.chatPreferencesSnapshot
        let key = RGChatPreferences.key(accountId: accountId, peerId: peerId)
        if value.isEmpty { values.removeValue(forKey: key) } else { values[key] = value }
        if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) { self.chatPreferencesJSON = json }
    }

    public func defaultOutgoingFormat(accountId: Int64, peerId: Int64) -> DefaultOutgoingFormat {
        let value = self.chatPreferences(accountId: accountId, peerId: peerId).formatting
        return value.flatMap(DefaultOutgoingFormat.init(rawValue:)) ?? self.defaultOutgoingFormat
    }

    public func panguSpacing(accountId: Int64, peerId: Int64) -> Bool {
        return self.chatPreferences(accountId: accountId, peerId: peerId).panguSpacing ?? self.panguSpacing
    }

    public func exportPreferences(categories: Set<RGBackupCategory>) -> RGSettingsBackup {
        let wrappers = Mirror(reflecting: self).children.compactMap { $0.value as? RGPreferenceCache }
        var values: [String: RGBackupValue] = [:]
        for (category, keys) in RGSettingsBackup.categoryKeys where categories.contains(category) {
            for key in keys {
                let storage = self.backupStorage(key: key, wrappers: wrappers)
                var raw: Any? = storage.object(forKey: key) ?? Self.defaultValues[key] ?? Self.groupDefaultValues[key]
                if key == RGBottomBarSettings.storageKey { raw = self.bottomBarSettings.storedValues }
                if key == Keys.chatListLines.rawValue { raw = self.chatListLines } // MARK: Regram
                if raw == nil && key == "forceBuiltInMic" { raw = false }
                if let raw, let value = RGBackupValue(propertyList: raw) { values[key] = value }
            }
        }
        return RGSettingsBackup(values: values)
    }

    @discardableResult
    public func applyPreferences(_ values: [String: RGBackupValue], resetCategories: Set<RGBackupCategory> = [], publishChanges: Bool = true) -> Set<String> {
        // MARK: Regram — old backups carry only the remember-last flag; it must replace a newer mode too.
        var values = values
        if values[RGBottomBarSettings.storageKey] == nil,
           ["showTabNames", "hideTabBar", "tabBarWidthPercent", "native.showContactsTab", "native.showCallsTab"].contains(where: { values[$0] != nil }) {
            var layout = resetCategories.contains(.appearance) ? RGBottomBarSettings() : self.bottomBarSettings
            if case let .bool(value)? = values["showTabNames"] { layout.showLabels = value }
            if case let .bool(value)? = values["hideTabBar"] { layout.isBottomBarVisible = !value }
            if case let .integer(value)? = values["tabBarWidthPercent"], let percent = Int32(exactly: value) {
                layout.automaticWidth = percent == 0
                layout.buttonWidthFillRatio = RGTabBarLayoutPolicy.normalizedPercent(percent)
            }
            if case let .bool(value)? = values["native.showContactsTab"] { layout.setVisible(.contacts, visible: value) }
            if case let .bool(value)? = values["native.showCallsTab"] { layout.setVisible(.calls, visible: value) }
            values[RGBottomBarSettings.storageKey] = .dictionary(layout.storedValues)
        }
        values = RGSettingsBackup(values: values).values
        if values["features.chatListStartupFolderMode"] == nil, case let .bool(rememberLast)? = values["rememberLastFolder"] {
            values["features.chatListStartupFolderMode"] = .string(rememberLast ? "last" : "telegram")
        }
        let wrappers = Mirror(reflecting: self).children.compactMap { $0.value as? RGPreferenceCache }
        let resetKeys = Set(resetCategories.flatMap { RGSettingsBackup.categoryKeys[$0] ?? [] })
        let changedKeys = Set(values.keys).union(resetKeys)
        for key in resetKeys where !key.hasPrefix("native.") {
            let storage = self.backupStorage(key: key, wrappers: wrappers)
            storage.removeObject(forKey: key)
        }
        for (key, value) in values where RGSettingsBackup.category(for: key) != nil && !key.hasPrefix("native.") {
            let storage = self.backupStorage(key: key, wrappers: wrappers)
            if key == Keys.downloadSpeedBoost.rawValue, value == .string("maximum") { storage.set("medium", forKey: key) }
            else if key == Keys.chatListLines.rawValue { // MARK: Regram — imported removed modes cannot reappear in backups.
                let count = (value.propertyList as? String).flatMap(ChatListLines.init(rawValue:)) ?? .two
                storage.set(count.rawValue, forKey: key)
            }
            else { storage.set(value.propertyList, forKey: key) }
        }
        if changedKeys.contains(where: { $0.hasPrefix("font") }) {
            // Update the stored revision before clearing wrappers, without an early font notification.
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Keys.fontAssetsRevision.rawValue) + 1, forKey: Keys.fontAssetsRevision.rawValue)
        }
        for wrapper in wrappers { wrapper.invalidatePreferenceCache() }
        if !changedKeys.isDisjoint(with: ["messageFilterRules", "blockedPeerIds", "messageFilterDisabledPeerIds"]) {
            self.notifyContentFiltersChanged(postNotification: false)
        }
        if changedKeys.contains("antiRevokePeerIds") {
            self.antiRevokeCacheLock.lock(); self.cachedAntiRevokePeerIds = nil; self.antiRevokeCacheLock.unlock()
        }
        self.synchronizeShared()
        // MARK: Regram — restore/reset transport preferences into the extension store as well.
        if !changedKeys.isDisjoint(with: ["customDoHEnabled", "customDoHEndpoint", "ipVersionPolicy", "disableBackupAddresses", "localDNSForProxyHost"]) {
            if self.networkPolicy.dohEnabled { UserDefaults.standard.set(false, forKey: Keys.localDNSForProxyHost.rawValue) }
            if let shared = APP_GROUP_USER_DEFAULTS { self.networkPolicy.save(to: shared); shared.set(self.localDNSForProxyHost, forKey: Keys.localDNSForProxyHost.rawValue) }
        }
        if publishChanges { self.publishPreferenceChanges(changedKeys) }
        return changedKeys
    }

    /// A restore publishes only after account-manager preferences have also committed.
    public func publishPreferenceChanges(_ keys: Set<String>) {
        func touches(_ names: String...) -> Bool { !keys.isDisjoint(with: names) }
        let center = NotificationCenter.default
        if keys.contains(where: { $0.hasPrefix("font") }) { center.post(name: RGFontConfiguration.settingsChanged, object: nil) }
        if touches("bottomBarLayout", "showTabNames", "hideTabBar", "tabBarWidthPercent", "native.showContactsTab", "native.showCallsTab") { center.post(name: RGTabBarLayoutPolicy.settingsChanged, object: nil) }
        if touches("hideChatListSeparators", "compactChatList", "chatListLines") { center.post(name: Self.chatListSeparatorSettingsDidChange, object: nil) }
        if touches("messageFilterRules", "blockedPeerIds", "messageFilterDisabledPeerIds") { center.post(name: Self.contentFiltersDidChangeNotification, object: nil) }
        if touches("defaultVideoQuality") { center.post(name: RGVideoQualityPreference.settingsChanged, object: nil) }
        if touches("mediaLoadingExperiment") { center.post(name: RGMediaLoadingPolicy.settingsChanged, object: nil) }
        if touches("automaticallyRevealSpoilers") { center.post(name: Self.spoilerSettingsDidChange, object: nil) }
        if touches("revokedMarkerStyle", "revokedMarkerText", "revokedMarkerColor", "antiRevoke", "antiRevokePeerIds") { center.post(name: Self.revokedMarkerDidChange, object: nil) }
        if touches("messageSummaryEnabled") { center.post(name: Self.summarySettingsDidChange, object: nil) }
        if touches("features.enablePanguOnReceiving") { center.post(name: Self.featureMessagePresentationDidChange, object: nil) }
        if touches("sendWithReturnKey") { center.post(name: Self.inputSettingsDidChange, object: nil) }
        if touches("features.showFoldersInShareSheet") { center.post(name: Self.shareSettingsDidChange, object: nil) }
        if touches("fixLinkPreviews", "linkPreviewXHost", "linkPreviewInstagramHost") { center.post(name: RGLinkPreviewRules.didChangeNotification, object: nil) }
        if touches("customDoHEnabled", "customDoHEndpoint", "ipVersionPolicy", "disableBackupAddresses", "localDNSForProxyHost") { center.post(name: RGNetworkPolicy.didChange, object: nil) }
    }

    private func backupStorage(key: String, wrappers: [RGPreferenceCache]) -> UserDefaults {
        if let storage = wrappers.first(where: { $0.preferenceKey == key })?.preferenceStorage { return storage }
        if key == "pinnedMessageNotificationsExceptions" || key == "mentionsAndRepliesNotificationsExceptions" { return APP_GROUP_USER_DEFAULTS ?? .standard }
        return .standard
    }
















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

    @UserDefault(key: Keys.showRepostToStoryV2.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
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

    @UserDefault(key: Keys.contextShowEditHistory.rawValue)
    public var contextShowEditHistory: Bool

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

    // MARK: Regram — account-scoped inventory of real, generated message actions.
    public func availableContextMenuItems(accountPeerId: Int64) -> Set<RGContextMenuItemId> {
        let stored = UserDefaults.standard.stringArray(forKey: "rg_contextMenuObserved_\(accountPeerId)") ?? []
        return RGContextMenuItemId.standardItems.union(stored.compactMap(RGContextMenuItemId.init(rawValue:))).filter { $0.canBeCustomized }
    }

    public func recordAvailableContextMenuItems(_ items: Set<RGContextMenuItemId>, accountPeerId: Int64) {
        let key = "rg_contextMenuObserved_\(accountPeerId)"
        let old = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let updated = old.union(items.filter { $0.canBeCustomized }.map(\.rawValue))
        if updated != old { UserDefaults.standard.set(updated.sorted(), forKey: key) }
    }

    /// Reordering the visible subset preserves the slots/order of conditional, hidden actions.
    public func reorderVisibleContextMenuItems(_ items: [RGContextMenuItemId]) {
        let visible = Set(items)
        var iterator = items.makeIterator()
        self.contextMenuOrder = self.contextMenuOrder.map { item in
            return visible.contains(item) ? (iterator.next() ?? item) : item
        }
    }

    @UserDefault(key: Keys.contextMenuDisabledItems.rawValue)
    public var contextMenuDisabledItems: [String]

    /// Disabled actions are omitted from the message menu.
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
        case .editHistory: return self.contextShowEditHistory
        default: return !self.contextMenuDisabledItems.contains(id.rawValue)
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
        case .editHistory: self.contextShowEditHistory = value
        default:
            var disabled = Set(self.contextMenuDisabledItems)
            if value { disabled.remove(id.rawValue) } else { disabled.insert(id.rawValue) }
            self.contextMenuDisabledItems = disabled.sorted()
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

    @UserDefault(key: Keys.recentStickerLimit.rawValue)
    public var recentStickerLimit: Int32

    @UserDefault(key: Keys.defaultOutgoingFormatting.rawValue)
    public var defaultOutgoingFormatting: String

    public var recentStickerLimitValue: Int {
        let limit = self.recentStickerLimit
        return RGSimpleSettings.recentStickerLimitOptions.contains(limit) ? Int(limit) : 20
    }

    public var defaultOutgoingFormat: DefaultOutgoingFormat {
        return DefaultOutgoingFormat(rawValue: self.defaultOutgoingFormatting) ?? .none
    }

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
    
    public static let chatListSeparatorSettingsDidChange = Notification.Name("Regram.ChatListSeparatorSettingsDidChange")
    @UserDefault(key: Keys.hideChatListSeparators.rawValue)
    public var hideChatListSeparators: Bool

    @UserDefault(key: Keys.compactChatList.rawValue)
    public var compactChatList: Bool

    @UserDefault(key: Keys.chatListLines.rawValue)
    private var storedChatListLines: String
    // MARK: Regram — old backups and installed "3" values become the supported two-line mode.
    public var chatListLines: String {
        get { (ChatListLines(rawValue: storedChatListLines) ?? .two).rawValue }
        set { storedChatListLines = (ChatListLines(rawValue: newValue) ?? .two).rawValue }
    }

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
    
    

    
    @UserDefault(key: Keys.messageFilterKeywords.rawValue)
    public var messageFilterKeywords: [String]

    // MARK: Regram — message filter v2. JSON-encoded `[RGMessageFilterRule]`; see MessageFilter.swift.
    @UserDefault(key: Keys.messageFilterRules.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var messageFilterRulesJSON: String

    /// Posted whenever the message-filter rules or the hidden-sender list change. The chat history
    /// is rebuilt from a signal chain that only reacts to Postbox updates, so without an explicit
    /// notification a newly added rule would not take effect until some unrelated update happened
    /// to arrive.
    public static let contentFiltersDidChangeNotification = Notification.Name("RGSimpleSettings.contentFiltersDidChange")

    private func notifyContentFiltersChanged(postNotification: Bool = true) {
        self.contentFilterCacheLock.lock()
        self.cachedMessageFilterRules = nil
        self.cachedBlockedPeerIds = nil
        self.cachedMessageFilterDisabledPeerIds = nil
        self.contentFilterGenerationValue += 1
        self.contentFilterCacheLock.unlock()
        if postNotification { NotificationCenter.default.post(name: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil) }
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
    @UserDefault(key: Keys.blockedPeerIds.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
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
    @UserDefault(key: Keys.messageFilterDisabledPeerIds.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
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

    // MARK: Regram — chats anti-revoke is switched on for individually, from the chat's own profile.
    // `antiRevoke` still covers every chat; this list only adds chats while it is off. Kept in the
    // app group suite with `antiRevoke`, since the notification extension applies deletions too.
    @UserDefault(key: Keys.antiRevokePeerIds.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var antiRevokePeerIdsRaw: [String]

    /// Deletions are checked per message, so the decoded set is memoised.
    private let antiRevokeCacheLock = NSLock()
    private var cachedAntiRevokePeerIds: Set<Int64>?

    public var antiRevokePeerIds: Set<Int64> {
        get {
            self.antiRevokeCacheLock.lock()
            defer { self.antiRevokeCacheLock.unlock() }
            if let cached = self.cachedAntiRevokePeerIds {
                return cached
            }
            let decoded = Set(self.antiRevokePeerIdsRaw.compactMap { Int64($0) })
            self.cachedAntiRevokePeerIds = decoded
            return decoded
        }
        set {
            self.antiRevokeCacheLock.lock()
            self.antiRevokePeerIdsRaw = newValue.map { String($0) }
            self.cachedAntiRevokePeerIds = newValue
            self.antiRevokeCacheLock.unlock()
        }
    }

    /// Whether anti-revoke applies anywhere, so a deletion can take the upstream path untouched
    /// when it does not.
    public var isAntiRevokeActive: Bool {
        return self.antiRevoke || !self.antiRevokePeerIds.isEmpty
    }

    /// Whether messages revoked in `peerId` are kept: on for every chat, or for this one.
    public func isAntiRevokeEnabled(forPeer peerId: Int64) -> Bool {
        return self.antiRevoke || self.antiRevokePeerIds.contains(peerId)
    }

    public func setAntiRevokeEnabled(_ enabled: Bool, forPeer peerId: Int64) {
        var ids = self.antiRevokePeerIds
        if enabled {
            ids.insert(peerId)
        } else {
            ids.remove(peerId)
        }
        self.antiRevokePeerIds = ids
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
    public var sendWithReturnKey: Bool {
        didSet { NotificationCenter.default.post(name: Self.inputSettingsDidChange, object: nil) }
    }
    public static let inputSettingsDidChange = Notification.Name("Regram.InputSettingsDidChange")
    public static let shareSettingsDidChange = Notification.Name("Regram.ShareSettingsDidChange")

    // MARK: Regram — pin chats past the server's limit. The server keeps the first N pins (N is the
    // account's real limit); the rest are local to this device. See RGLocalPinnedChats in TelegramCore.
    @UserDefault(key: Keys.unlimitedPinnedChats.rawValue)
    public var unlimitedPinnedChats: Bool

    /// Legacy per-app overflow records, read when migrating local pins into account preferences.
    /// New pin writes use the same Postbox transaction as the chat-list order (RGLocalPinnedChats).
    public func localOverflowPinnedPeerIds(accountPeerId: Int64, groupId: Int32) -> [Int64] {
        return (UserDefaults.standard.stringArray(forKey: self.localOverflowPinnedKey(accountPeerId: accountPeerId, groupId: groupId)) ?? []).compactMap { Int64($0) }
    }

    public func setLocalOverflowPinnedPeerIds(_ peerIds: [Int64], accountPeerId: Int64, groupId: Int32) {
        let key = self.localOverflowPinnedKey(accountPeerId: accountPeerId, groupId: groupId)
        if peerIds.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(peerIds.map { String($0) }, forKey: key)
        }
    }

    private func localOverflowPinnedKey(accountPeerId: Int64, groupId: Int32) -> String {
        return "rg_localOverflowPinned_\(accountPeerId)_\(groupId)"
    }

    // MARK: Regram — keep the text a message had before each edit, see RGEditHistoryMessageAttribute.
    @UserDefault(key: Keys.saveEditHistory.rawValue)
    public var saveEditHistory: Bool

    // MARK: Regram — after joining a group or channel, offer to add it to a chat folder
    // (RGJoinedChatFolderPicker).
    @UserDefault(key: Keys.chooseFolderAfterJoining.rawValue)
    public var chooseFolderAfterJoining: Bool

    // MARK: Regram — recently opened chats, newest first, per account. Shown under the back button's
    // long-press menu and on the Recent Chats page (Chats tab long-press).
    @UserDefault(key: Keys.recentChatsEnabled.rawValue)
    public var recentChatsEnabled: Bool

    public static let recentChatsLimit = 50

    public func recentChatPeerIds(accountPeerId: Int64) -> [Int64] {
        return (UserDefaults.standard.stringArray(forKey: self.recentChatsKey(accountPeerId: accountPeerId)) ?? []).compactMap { Int64($0) }
    }

    public func addRecentChat(_ peerId: Int64, accountPeerId: Int64) {
        guard self.recentChatsEnabled else {
            return
        }
        var peerIds = self.recentChatPeerIds(accountPeerId: accountPeerId)
        if peerIds.first == peerId {
            return
        }
        peerIds.removeAll(where: { $0 == peerId })
        peerIds.insert(peerId, at: 0)
        if peerIds.count > RGSimpleSettings.recentChatsLimit {
            peerIds.removeSubrange(RGSimpleSettings.recentChatsLimit...)
        }
        self.setRecentChatPeerIds(peerIds, accountPeerId: accountPeerId)
    }

    public func removeRecentChat(_ peerId: Int64, accountPeerId: Int64) {
        var peerIds = self.recentChatPeerIds(accountPeerId: accountPeerId)
        peerIds.removeAll(where: { $0 == peerId })
        self.setRecentChatPeerIds(peerIds, accountPeerId: accountPeerId)
    }

    public func clearRecentChats(accountPeerId: Int64) {
        self.setRecentChatPeerIds([], accountPeerId: accountPeerId)
    }

    private func setRecentChatPeerIds(_ peerIds: [Int64], accountPeerId: Int64) {
        let key = self.recentChatsKey(accountPeerId: accountPeerId)
        if peerIds.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(peerIds.map { String($0) }, forKey: key)
        }
    }

    private func recentChatsKey(accountPeerId: Int64) -> String {
        return "rg_recentChats_\(accountPeerId)"
    }

    // MARK: Regram — double tap on a message, see `MessageDoubleTapActionV2`.
    @UserDefault(key: Keys.messageDoubleTapAction.rawValue)
    public var messageDoubleTapAction: String

    @UserDefault(key: Keys.messageDoubleTapActionWithoutEditPermission.rawValue)
    public var messageDoubleTapActionWithoutEditPermission: String

    /// The action for a message, given whether this account may edit it. Editing a message that
    /// cannot be edited falls back to the default reaction.
    public func resolvedMessageDoubleTapAction(canEditMessage: Bool) -> MessageDoubleTapActionV2 {
        var action = MessageDoubleTapActionV2(rawValue: self.messageDoubleTapAction) ?? .sendReaction
        if !canEditMessage, let override = MessageDoubleTapActionV2(rawValue: self.messageDoubleTapActionWithoutEditPermission) {
            action = override
        }
        if action == .edit && !canEditMessage {
            return .sendReaction
        }
        return action
    }

    // MARK: Regram — append the message id to the timestamp of group and channel messages.
    @UserDefault(key: Keys.showMessageId.rawValue)
    public var showMessageId: Bool

    // MARK: Regram — automatic reveal is separate from each message's manual reveal state.
    public static let spoilerSettingsDidChange = Notification.Name("Regram.SpoilerSettingsDidChange")

    @UserDefault(key: Keys.automaticallyRevealSpoilers.rawValue)
    public var automaticallyRevealSpoilers: Bool {
        didSet {
            if automaticallyRevealSpoilers != oldValue {
                NotificationCenter.default.post(name: Self.spoilerSettingsDidChange, object: nil)
            }
        }
    }

    // MARK: Regram — show when a forwarded message was originally sent, next to its source.
    @UserDefault(key: Keys.showForwardedMessageDate.rawValue)
    public var showForwardedMessageDate: Bool
    
    @UserDefault(key: Keys.pinnedMessageNotifications.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var pinnedMessageNotifications: String
    
    @UserDefault(key: Keys.mentionsAndRepliesNotifications.rawValue, userDefaults: APP_GROUP_USER_DEFAULTS ?? .standard)
    public var mentionsAndRepliesNotifications: String
    
    @UserDefault(key: Keys.primaryUserId.rawValue)
    public var primaryUserId: String

    @UserDefault(key: Keys.dismissedRGSuggestions.rawValue)
    public var dismissedRGSuggestions: [String]


    @UserDefault(key: Keys.transcriptionBackend.rawValue)
    public var transcriptionBackend: String

    // MARK: Regram — speech configuration and link preview preferences.
    @UserDefault(key: Keys.sttBaseURL.rawValue)
    public var sttBaseURL: String
    @UserDefault(key: Keys.sttEndpoint.rawValue)
    public var sttEndpoint: String
    @UserDefault(key: Keys.sttModel.rawValue)
    public var sttModel: String
    @UserDefault(key: Keys.sttLanguage.rawValue)
    public var sttLanguage: String
    @UserDefault(key: Keys.sttPrompt.rawValue)
    public var sttPrompt: String
    @UserDefault(key: Keys.fixLinkPreviews.rawValue)
    public var fixLinkPreviews: Bool
    @UserDefault(key: Keys.linkPreviewXHost.rawValue)
    public var linkPreviewXHost: String
    @UserDefault(key: Keys.linkPreviewInstagramHost.rawValue)
    public var linkPreviewInstagramHost: String

    @UserDefault(key: Keys.translationLLMAPIFormat.rawValue)
    public var translationLLMAPIFormat: String
    @UserDefault(key: Keys.translationLLMBaseURL.rawValue)
    public var translationLLMBaseURL: String
    @UserDefault(key: Keys.translationLLMEndpoint.rawValue)
    public var translationLLMEndpoint: String
    @UserDefault(key: Keys.translationLLMModel.rawValue)
    public var translationLLMModel: String
    @UserDefault(key: Keys.translationLLMPrompt.rawValue)
    public var translationLLMPrompt: String
    @UserDefault(key: Keys.translationLLMUseContext.rawValue)
    public var translationLLMUseContext: Bool
    @UserDefault(key: Keys.translationLLMTemperatureTenths.rawValue)
    public var translationLLMTemperatureTenths: Int32
    public var translationLLMTemperatureTenthsValue: Int32 { return max(0, min(10, self.translationLLMTemperatureTenths)) }

    @UserDefault(key: Keys.translationBackend.rawValue)
    public var translationBackend: String

    @UserDefault(key: Keys.customAppBadge.rawValue)
    private var storedCustomAppBadge: String

    public var customAppBadge: String {
        get { RGAppBadgeNames.canonicalName(self.storedCustomAppBadge) }
        set { self.storedCustomAppBadge = RGAppBadgeNames.canonicalName(newValue) }
    }

    @UserDefault(key: Keys.canUseNY.rawValue)
    public var canUseNY: Bool

    @UserDefault(key: Keys.nyStyle.rawValue)
    public var nyStyle: String

    @UserDefault(key: Keys.wideTabBar.rawValue)
    public var wideTabBar: Bool

    @UserDefault(key: Keys.tabBarWidthPercent.rawValue)
    public var tabBarWidthPercent: Int32 {
        didSet {
            if tabBarWidthPercent != oldValue { NotificationCenter.default.post(name: RGTabBarLayoutPolicy.settingsChanged, object: nil) }
        }
    }
    
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
        return translationBackend == "gtranslate" ? .google : (TranslationBackend(rawValue: translationBackend) ?? .default)
    }

    /// Backends served by a third-party web endpoint rather than by Telegram or by the OS. Those
    /// translate a plain string, so messages have to be routed through the via-text path.
    public var translationBackendIsExternal: Bool {
        switch translationBackendEnum {
        case .google, .googleCN, .microsoft, .yandex, .transmart, .llm:
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
        case RGSimpleSettings.DownloadSpeedBoostValues.enabled.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 512 * 1024
        default:
            return `default`
    }
}

public func getRGMaxPendingParts(_ default: Int) -> Int {
    let currentDownloadSetting = RGSimpleSettings.shared.downloadSpeedBoost
    switch (currentDownloadSetting) {
        case RGSimpleSettings.DownloadSpeedBoostValues.enabled.rawValue:
            return 8
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

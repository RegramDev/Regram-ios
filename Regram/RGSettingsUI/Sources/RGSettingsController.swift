import RGSwiftUI
// MARK: Regram
import RGLogging
import RGSimpleSettings
import RGStrings
import RGAPIToken

import RGItemListUI
import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import MtProtoKit
import MessageUI
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import AppBundle
import WebKit
import PeerNameColorScreen
import UndoUI

// MARK: Regram — stable category destinations shared with the Pro settings hub.
public enum RGSettingsPage: String {
    case home, appearance, folders, chatList, profiles, stories, translation, transcription
    case messageActions, media, photos, stickers, recording, input, transfer, privacy, app
    public var titleKey: String { "Settings.Category." + self.rawValue }
}

private enum RGControllerSection: Int32, RGItemListSection {
    case trending
    case content
    case tabs
    case folders
    case chatList
    case profiles
    case stories
    case translation
    case calls
    case photo
    case stickers
    case videoNotes
    case contextMenu
    case accountColors
    case other
    case messageActions
    case media
    case recording
    case input
    case transfer
}

private enum RGBoolSetting: String {
    case showFoldersInShareSheet
    case tapMessageRowToOpenContextMenu
    case confirmUnpin
    case hideSavedAndArchivedMessagesInList
    case hidePrivateChatActivities
    case hideFolderUnreadCount
    case showArchiveInFolders
    case openArchiveOnPull
    case stayAtLatestMessageAfterRefresh
    case hideTopStories
    case disableChatAvatarStories
    case hideTabBarPermissionWarnings
    case disableCommunityChatGrouping
    case bottomUpGlobalSearchResults
    case keepNewChatsVisibleAtTop

    case hidePhoneInSettings
    case showTabNames
    case showContactsTab
    case showCallsTab
    case foldersAtBottom
    case startTelescopeWithRearCam
    case hideStories
    case uploadSpeedBoost
    case downloadSpeedBoost
    case mediaLoadingExperiment
    case showMediaMetadata // MARK: Regram
    case showProfileId
    case warnOnStoriesOpen
    case sendWithReturnKey
    case chooseFolderAfterJoining
    case sendLargePhotos
    case storyStealthMode
    case disableSwipeToRecordStory
    case disableDeleteChatSwipeOption
    case quickTranslateButton
    case hideReactions
    case showRepostToStory
    case contextShowSelectFromUser
    case contextShowSaveToCloud
    case contextShowHideForwardName
    case contextShowRestrict
    case contextShowReport
    case contextShowReply
    case contextShowPin
    case contextShowSaveMedia
    case contextShowMessageReplies
    case contextShowJson
    // MARK: Regram
    case profileDefaultTabGroupsInCommon
    case disableScrollToNextChannel
    case disableScrollToNextTopic
    case disableChatSwipeOptions
    case disableGalleryCamera
    case disableGalleryCameraPreview
    case disableSendAsButton
    case disableSnapDeletionEffect
    case stickerTimestamp
    case hideRecordingButton
    case hideTabBar
    case showDC
    case showCreationDate
    case showRegDate
    case compactChatList
    case hideChatListSeparators
    case unlimitedPinnedChats
    case showMessageId
    case automaticallyRevealSpoilers
    case showForwardedMessageDate
    case compactFolderNames
    case allChatsHidden
    case defaultEmojisFirst
    case messageDoubleTapActionOutgoingEdit
    case wideChannelPosts
    case forceEmojiTab
    case forceBuiltInMic
    case secondsInMessages
    case hideChannelBottomButton
    case confirmCalls
    case enableVoipTcp
    case nyStyleSnow
    case nyStyleLightning
}

private enum RGOneFromManySetting: String {
    case chatListSwipeAction
    case chatListFolderTabDisplayMode
    case startupFolder
    case communityAvatarTapAction
    case videoPIPSwipeDirection

    case nyStyle
    case defaultVideoQuality
    case allChatsTitleLengthOverride
//    case allChatsFolderPositionOverride
    case translationBackend
    case recentStickerLimit
    case chatListLines
    case messageDoubleTapAction
    case messageDoubleTapActionWithoutEditPermission
}

private enum RGSliderSetting: String {
    case accountColorsSaturation
    case outgoingPhotoQuality
    case stickerSize
}

private enum RGDisclosureLink: String {
    case groupProfileSettings, textStyleMenu, inlineBotRules


    case contentSettings
    case languageSettings
    case llmTranslationSettings
    // MARK: Regram
    case contextMenuOrder
    case bottomBarLayout
}

private struct PeerNameColorScreenState: Equatable {
    var updatedNameColor: PeerNameColor?
    var updatedBackgroundEmojiId: Int64?
}

private struct RGSettingsControllerState: Equatable {
}

private typealias RGControllerEntry = RGItemListUIEntry<RGControllerSection, RGBoolSetting, RGSliderSetting, RGOneFromManySetting, RGDisclosureLink, AnyHashable>

private func RGControllerEntries(presentationData: PresentationData, callListSettings: CallListSettings, experimentalUISettings: ExperimentalUISettings, appConfiguration: AppConfiguration, nameColors: PeerNameColors, state: RGSettingsControllerState, page: RGSettingsPage, startupFolderTitle: String) -> [RGControllerEntry] {
    
    let lang = presentationData.strings.rgLanguageCode
    let strings = presentationData.strings
    let newStr = strings.Settings_New
    var entries: [RGControllerEntry] = []
    
    let id = RGItemListCounter()
    
    
    
    if RGSimpleSettings.shared.canUseNY {
        entries.append(.header(id: id.count, section: .trending, text: i18n("Settings.NY.Header", lang), badge: newStr))
        entries.append(.toggle(id: id.count, section: .trending, settingName: .nyStyleSnow, value: RGSimpleSettings.shared.nyStyle == RGSimpleSettings.NYStyle.snow.rawValue, text: i18n("Settings.NY.Style.snow", lang), enabled: true))
        entries.append(.toggle(id: id.count, section: .trending, settingName: .nyStyleLightning, value: RGSimpleSettings.shared.nyStyle == RGSimpleSettings.NYStyle.lightning.rawValue, text: i18n("Settings.NY.Style.lightning", lang), enabled: true))
        // entries.append(.oneFromManySelector(id: id.count, section: .trending, settingName: .nyStyle, text: i18n("Settings.NY.Style", lang), value: i18n("Settings.NY.Style.\(RGSimpleSettings.shared.nyStyle)", lang), enabled: true))
        entries.append(.notice(id: id.count, section: .trending, text: i18n("Settings.NY.Notice", lang)))
    } else {
        id.increment(3)
    }
    
    if appConfiguration.rgWebSettings.global.canEditSettings {
        entries.append(.disclosure(id: id.count, section: .content, link: .contentSettings, text: i18n("Settings.ContentSettings", lang)))
    } else {
        id.increment(1)
    }
    
    entries.append(.header(id: id.count, section: .tabs, text: i18n("Settings.Tabs.Header", lang), badge: nil))
    entries.append(.disclosure(id: id.count, section: .tabs, link: .bottomBarLayout, text: i18n("Settings.Tabs.Customize", lang)))
    
    entries.append(.header(id: id.count, section: .folders, text: strings.Settings_ChatFolders.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .foldersAtBottom, value: experimentalUISettings.foldersTabAtBottom, text: i18n("Settings.Folders.BottomTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .allChatsHidden, value: RGSimpleSettings.shared.allChatsHidden, text: i18n("Settings.Folders.AllChatsHidden", lang, strings.ChatList_Tabs_AllChats), enabled: true))
    #if DEBUG
//    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsFolderPositionOverride, text: i18n("Settings.Folders.AllChatsPlacement", lang), value: i18n("Settings.Folders.AllChatsPlacement.\(RGSimpleSettings.shared.allChatsFolderPositionOverride)", lang), enabled: true))
    #endif
    entries.append(.toggle(id: id.count, section: .folders, settingName: .compactFolderNames, value: RGSimpleSettings.shared.compactFolderNames, text: i18n("Settings.Folders.CompactNames", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsTitleLengthOverride, text: i18n("Settings.Folders.AllChatsTitle", lang), value: i18n("Settings.Folders.AllChatsTitle.\(RGSimpleSettings.shared.allChatsTitleLengthOverride)", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .startupFolder, text: "features.ChatListStartupFolder".i18n(lang), value: startupFolderTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .folders, text: i18n("Settings.Folders.RememberLast.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .chooseFolderAfterJoining, value: RGSimpleSettings.shared.chooseFolderAfterJoining, text: i18n("JoinFolder.Setting", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .folders, text: i18n("JoinFolder.Setting.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .chatList, text: i18n("Settings.ChatList.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactChatList, value: RGSimpleSettings.shared.compactChatList, text: i18n("Settings.CompactChatList", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .chatList, settingName: .chatListLines, text: "Settings.ChatList.Lines".i18n(lang), value: "Settings.ChatList.Lines.\(RGSimpleSettings.shared.chatListLines)".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableDeleteChatSwipeOption, value: !RGSimpleSettings.shared.disableDeleteChatSwipeOption, text: i18n("Settings.DeleteChatSwipeOption", lang), enabled: RGSimpleSettings.shared.chatListSwipeActionMode.allowsQuickActions))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .hideChatListSeparators, value: RGSimpleSettings.shared.hideChatListSeparators, text: "Settings.ChatList.HideSeparators".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .unlimitedPinnedChats, value: RGSimpleSettings.shared.unlimitedPinnedChats, text: i18n("Settings.UnlimitedPinnedChats", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .chatList, text: i18n("Settings.UnlimitedPinnedChats.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .profiles, text: i18n("Settings.Profiles.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showProfileId, value: RGSimpleSettings.shared.showProfileId, text: i18n("Settings.ShowProfileID", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showDC, value: RGSimpleSettings.shared.showDC, text: i18n("Settings.ShowDC", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showRegDate, value: RGSimpleSettings.shared.showRegDate, text: i18n("Settings.ShowRegDate", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowRegDate.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showCreationDate, value: RGSimpleSettings.shared.showCreationDate, text: i18n("Settings.ShowCreationDate", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowCreationDate.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .profileDefaultTabGroupsInCommon, value: RGSimpleSettings.shared.profileDefaultTabGroupsInCommon, text: i18n("Settings.Profiles.DefaultTabGroupsInCommon", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.Profiles.DefaultTabGroupsInCommon.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .confirmCalls, value: RGSimpleSettings.shared.confirmCalls, text: i18n("Settings.CallConfirmation", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.CallConfirmation.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .stories, text: strings.AutoDownloadSettings_Stories.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .hideStories, value: RGSimpleSettings.shared.hideStories, text: i18n("Settings.Stories.Hide", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .disableSwipeToRecordStory, value: RGSimpleSettings.shared.disableSwipeToRecordStory, text: i18n("Settings.Stories.DisableSwipeToRecord", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .warnOnStoriesOpen, value: RGSimpleSettings.shared.warnOnStoriesOpen, text: i18n("Settings.Stories.WarnBeforeView", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .showRepostToStory, value: RGSimpleSettings.shared.showRepostToStoryV2, text: strings.Share_RepostToStory.replacingOccurrences(of: "\n", with: " "), enabled: true))
    if RGSimpleSettings.shared.canUseStealthMode {
        entries.append(.toggle(id: id.count, section: .stories, settingName: .storyStealthMode, value: RGSimpleSettings.shared.storyStealthMode, text: strings.Story_StealthMode_Title, enabled: true))
        entries.append(.notice(id: id.count, section: .stories, text: strings.Story_StealthMode_ControlText))
    } else {
        id.increment(2)
    }

    
    entries.append(.header(id: id.count, section: .translation, text: strings.Localization_TranslateMessages.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .translation, settingName: .translationBackend, text: i18n("Settings.Translation.Backend", lang), value: i18n("Settings.Translation.Backend.\(RGSimpleSettings.shared.translationBackendEnum.rawValue)", lang), enabled: true))
    if !RGSimpleSettings.shared.translationBackendIsExternal {
        entries.append(.notice(id: id.count, section: .translation, text: i18n("Settings.Translation.Backend.Notice", lang, "Settings.Translation.Backend.\(RGSimpleSettings.TranslationBackend.google.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.disclosure(id: id.count, section: .translation, link: .llmTranslationSettings, text: "LLMTranslation.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .translation, settingName: .quickTranslateButton, value: RGSimpleSettings.shared.quickTranslateButton, text: i18n("Settings.Translation.QuickTranslateButton", lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .translation, link: .languageSettings, text: strings.Localization_TranslateEntireChat))
    entries.append(.notice(id: id.count, section: .translation, text: i18n("Common.NoTelegramPremiumNeeded", lang, strings.Settings_Premium)))

    entries.append(.header(id: id.count, section: .recording, text: strings.Privacy_VoiceMessages.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .recording, settingName: .forceBuiltInMic, value: RGSimpleSettings.shared.forceBuiltInMic, text: i18n("Settings.forceBuiltInMic", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .recording, text: i18n("Settings.forceBuiltInMic.Notice", lang)))

    entries.append(.header(id: id.count, section: .calls, text: strings.Calls_TabTitle.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .calls, settingName: .enableVoipTcp, value: experimentalUISettings.enableVoipTcp, text: "Settings.Calls.ForceTCP".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .calls, text: "Common.KnowWhatYouDo".i18n(lang)))
    
    entries.append(.header(id: id.count, section: .photo, text: strings.NetworkUsageSettings_MediaImageDataSection, badge: nil))
    entries.append(.header(id: id.count, section: .photo, text: strings.PhotoEditor_QualityTool.uppercased(), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .photo, settingName: .outgoingPhotoQuality, value: RGSimpleSettings.shared.outgoingPhotoQuality))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.Quality.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .photo, settingName: .sendLargePhotos, value: RGSimpleSettings.shared.sendLargePhotos, text: i18n("Settings.Photo.SendLarge", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.SendLarge.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .stickers, text: strings.StickerPacksSettings_Title.uppercased(), badge: nil))
    entries.append(.header(id: id.count, section: .stickers, text: i18n("Settings.Stickers.Size", lang), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .stickers, settingName: .stickerSize, value: RGSimpleSettings.shared.stickerSize))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .stickerTimestamp, value: RGSimpleSettings.shared.stickerTimestamp, text: i18n("Settings.Stickers.Timestamp", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .stickers, settingName: .recentStickerLimit, text: i18n("Settings.Stickers.RecentLimit", lang), value: String(RGSimpleSettings.shared.recentStickerLimitValue), enabled: true))
    
    
    entries.append(.header(id: id.count, section: .videoNotes, text: i18n("Settings.VideoNotes.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .videoNotes, settingName: .startTelescopeWithRearCam, value: RGSimpleSettings.shared.startTelescopeWithRearCam, text: i18n("Settings.VideoNotes.StartWithRearCam", lang), enabled: true))
    

    // MARK: Regram — the individual switches moved to their own screen so they can also be dragged
    // into an order; keeping a copy here would give the same setting two places to disagree.
    entries.append(.header(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu", lang), badge: nil))
    entries.append(.disclosure(id: id.count, section: .contextMenu, link: .contextMenuOrder, text: i18n("Settings.ContextMenu.Customize", lang)))
    entries.append(.notice(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Header", lang), badge: nil))
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation", lang), badge: nil))
    let accountColorSaturation = RGSimpleSettings.shared.accountColorsSaturation
    entries.append(.percentageSlider(id: id.count, section: .accountColors, settingName: .accountColorsSaturation, value: accountColorSaturation))
//    let nameColor: PeerNameColor
//    if let updatedNameColor = state.updatedNameColor {
//        nameColor = updatedNameColor
//    } else {
//        nameColor = .blue
//    }
//    let _ = nameColors.get(nameColor, dark: presentationData.theme.overallDarkAppearance)
//    entries.append(.peerColorPicker(id: entries.count, section: .other,
//        colors: nameColors,
//        currentColor: nameColor, // TODO: PeerNameColor(rawValue: <#T##Int32#>)
//        currentSaturation: accountColorSaturation
//    ))
    
    if accountColorSaturation == 0 {
        id.increment(100)
        entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(strings.UserInfo_FirstNamePlaceholder) \(strings.UserInfo_LastNamePlaceholder)", color:         presentationData.theme.chat.message.incoming.accentTextColor))
    } else {
        id.increment(200)
        for index in nameColors.displayOrder.prefix(3) {
            let color: PeerNameColor = PeerNameColor(rawValue: index)
            let colors = nameColors.get(color, dark: presentationData.theme.overallDarkAppearance)
            entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(strings.UserInfo_FirstNamePlaceholder) \(strings.UserInfo_LastNamePlaceholder)", color: colors.main))
        }
    }
    entries.append(.notice(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation.Notice", lang)))
    
    id.increment(10000)
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .hideChannelBottomButton, value: !RGSimpleSettings.shared.hideChannelBottomButton, text: i18n("Settings.showChannelBottomButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .wideChannelPosts, value: RGSimpleSettings.shared.wideChannelPosts, text: i18n("Settings.wideChannelPosts", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .secondsInMessages, value: RGSimpleSettings.shared.secondsInMessages, text: i18n("Settings.secondsInMessages", lang), enabled: true))
    // MARK: Regram — double tap v2 replaces the old "double tap to edit your messages" switch.
    entries.append(.oneFromManySelector(id: id.count, section: .messageActions, settingName: .messageDoubleTapAction, text: "DoubleTap.Action".i18n(lang), value: "DoubleTap.Action.\(RGSimpleSettings.shared.messageDoubleTapAction)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .messageActions, settingName: .messageDoubleTapActionWithoutEditPermission, text: "DoubleTap.WithoutEditPermission".i18n(lang), value: "DoubleTap.Action.\(RGSimpleSettings.shared.messageDoubleTapActionWithoutEditPermission)".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .showMessageId, value: RGSimpleSettings.shared.showMessageId, text: "Settings.ShowMessageId".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .automaticallyRevealSpoilers, value: RGSimpleSettings.shared.automaticallyRevealSpoilers, text: "Settings.AutomaticallyRevealSpoilers".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .messageActions, text: "Settings.AutomaticallyRevealSpoilers.Notice".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .showForwardedMessageDate, value: RGSimpleSettings.shared.showForwardedMessageDate, text: "Settings.ShowForwardedMessageDate".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .input, settingName: .hideRecordingButton, value: !RGSimpleSettings.shared.hideRecordingButton, text: i18n("Settings.RecordingButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .disableSnapDeletionEffect, value: !RGSimpleSettings.shared.disableSnapDeletionEffect, text: i18n("Settings.SnapDeletionEffect", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .input, settingName: .disableSendAsButton, value: !RGSimpleSettings.shared.disableSendAsButton, text: i18n("Settings.SendAsButton", lang, strings.Conversation_SendMesageAs), enabled: true))
    entries.append(.toggle(id: id.count, section: .recording, settingName: .disableGalleryCamera, value: !RGSimpleSettings.shared.disableGalleryCamera, text: i18n("Settings.GalleryCamera", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .recording, settingName: .disableGalleryCameraPreview, value: !RGSimpleSettings.shared.disableGalleryCameraPreview, text: i18n("Settings.GalleryCameraPreview", lang), enabled: !RGSimpleSettings.shared.disableGalleryCamera))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .disableScrollToNextChannel, value: !RGSimpleSettings.shared.disableScrollToNextChannel, text: i18n("Settings.PullToNextChannel", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .disableScrollToNextTopic, value: !RGSimpleSettings.shared.disableScrollToNextTopic, text: i18n("Settings.PullToNextTopic", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .hideReactions, value: RGSimpleSettings.shared.hideReactions, text: i18n("Settings.HideReactions", lang), enabled: true))
    entries.append(.header(id: id.count, section: .transfer, text: "Diagnostics.Download".i18n(lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .transfer, settingName: .uploadSpeedBoost, value: RGSimpleSettings.shared.uploadSpeedBoost, text: i18n("Settings.UploadsBoost", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .transfer, settingName: .downloadSpeedBoost, value: RGSimpleSettings.shared.downloadSpeedBoost != RGSimpleSettings.DownloadSpeedBoostValues.none.rawValue, text: i18n("Settings.DownloadsBoost", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .transfer, text: i18n("Settings.DownloadsBoost.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .media, settingName: .mediaLoadingExperiment, value: RGSimpleSettings.shared.mediaLoadingExperiment, text: i18n("Settings.MediaLoadingExperiment", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .media, text: i18n("Settings.MediaLoadingExperiment.Notice", lang)))
    entries.append(.oneFromManySelector(id: id.count, section: .media, settingName: .defaultVideoQuality, text: i18n("Settings.DefaultVideoQuality", lang), value: i18n("Settings.DefaultVideoQuality.\(RGSimpleSettings.shared.defaultVideoQuality)", lang), enabled: true))
    // MARK: Regram — "Media Info" in the photo/video viewer's menu.
    entries.append(.toggle(id: id.count, section: .media, settingName: .showMediaMetadata, value: RGSimpleSettings.shared.showMediaMetadata, text: i18n("MediaMetadata.Setting", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .media, text: i18n("MediaMetadata.Setting.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .input, settingName: .sendWithReturnKey, value: RGSimpleSettings.shared.sendWithReturnKey, text: i18n("Settings.SendWithReturnKey", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .forceEmojiTab, value: RGSimpleSettings.shared.forceEmojiTab, text: i18n("Settings.ForceEmojiTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .defaultEmojisFirst, value: RGSimpleSettings.shared.defaultEmojisFirst, text: i18n("Settings.DefaultEmojisFirst", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .stickers, text: i18n("Settings.DefaultEmojisFirst.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .content, settingName: .hidePhoneInSettings, value: RGSimpleSettings.shared.hidePhoneInSettings, text: i18n("Settings.HidePhoneInSettingsUI", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("Settings.HidePhoneInSettingsUI.Notice", lang)))
    

    // MARK: Regram — chat, search and interface options.
    entries.append(.toggle(id: id.count, section: .folders, settingName: .showFoldersInShareSheet, value: RGSimpleSettings.shared.showFoldersInShareSheet, text: "features.ShowFoldersInShareSheet".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .tapMessageRowToOpenContextMenu, value: RGSimpleSettings.shared.tapMessageRowToOpenContextMenu, text: "features.TapMessageRowToOpenContextMenu".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .confirmUnpin, value: RGSimpleSettings.shared.confirmUnpin, text: "features.ConfirmUnpin".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .hideSavedAndArchivedMessagesInList, value: RGSimpleSettings.shared.hideSavedAndArchivedMessagesInList, text: "features.HideSavedAndArchivedMessagesInList".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .hidePrivateChatActivities, value: RGSimpleSettings.shared.hidePrivateChatActivities, text: "features.HidePrivateChatActivities".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .chatList, text: "features.HidePrivateChatActivities.Notice".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .hideFolderUnreadCount, value: RGSimpleSettings.shared.hideFolderUnreadCount, text: "features.HideFolderUnreadCount".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .showArchiveInFolders, value: RGSimpleSettings.shared.showArchiveInFolders, text: "features.ShowArchiveInFolders".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .openArchiveOnPull, value: RGSimpleSettings.shared.openArchiveOnPull, text: "features.OpenArchiveOnPull".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .messageActions, settingName: .stayAtLatestMessageAfterRefresh, value: RGSimpleSettings.shared.stayAtLatestMessageAfterRefresh, text: "features.StayAtLatestMessageAfterRefresh".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .hideTopStories, value: RGSimpleSettings.shared.hideTopStories, text: "features.HideTopStories".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .disableChatAvatarStories, value: RGSimpleSettings.shared.disableChatAvatarStories, text: "features.DisableChatAvatarStories".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .content, settingName: .hideTabBarPermissionWarnings, value: RGSimpleSettings.shared.hideTabBarPermissionWarnings, text: "features.HideTabBarPermissionWarnings".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableCommunityChatGrouping, value: RGSimpleSettings.shared.disableCommunityChatGrouping, text: "features.DisableCommunityChatGrouping".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .bottomUpGlobalSearchResults, value: RGSimpleSettings.shared.bottomUpGlobalSearchResults, text: "features.BottomUpGlobalSearchResults".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .keepNewChatsVisibleAtTop, value: RGSimpleSettings.shared.keepNewChatsVisibleAtTop, text: "features.KeepNewChatsVisibleAtTop".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .chatList, settingName: .chatListSwipeAction, text: "features.ChatListSwipeAction".i18n(lang), value: ("features.ChatListSwipeAction." + RGSimpleSettings.shared.chatListSwipeAction).i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .chatListFolderTabDisplayMode, text: "features.ChatListFolderTabDisplayMode".i18n(lang), value: ("features.ChatListFolderTabDisplayMode." + RGSimpleSettings.shared.chatListFolderTabDisplayMode).i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .chatList, settingName: .communityAvatarTapAction, text: "features.CommunityAvatarTapAction".i18n(lang), value: ("features.CommunityAvatarTapAction." + RGSimpleSettings.shared.communityAvatarTapAction).i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .media, settingName: .videoPIPSwipeDirection, text: "features.VideoPIPSwipeDirection".i18n(lang), value: ("features.VideoPIPSwipeDirection." + RGSimpleSettings.shared.videoPIPSwipeDirection).i18n(lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .profiles, link: .groupProfileSettings, text: "features.GroupProfileSettings".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .input, link: .textStyleMenu, text: "features.TextStyleMenu".i18n(lang)))

    entries.append(.disclosure(id: id.count, section: .messageActions, link: .inlineBotRules, text: "features.InlineBots.Title".i18n(lang)))
    let sections: [RGControllerSection]
    switch page {
    case .home, .transcription: sections = []
    case .input: sections = [.input]
    case .transfer: sections = [.transfer, .calls]
    case .privacy: sections = [.content]
    case .appearance: sections = [.tabs, .accountColors, .trending]
    case .folders: sections = [.folders]
    case .chatList: sections = [.chatList]
    case .profiles: sections = [.profiles]
    case .stories: sections = [.stories]
    case .translation: sections = [.translation]
    case .messageActions: sections = [.contextMenu, .messageActions]
    case .media: sections = [.media]
    case .photos: sections = [.photo]
    case .stickers: sections = [.stickers]
    case .recording: sections = [.recording, .videoNotes]
    case .app: sections = [.content] // MARK: Regram — legacy page links retain their remaining privacy options.
    }
    let allowed = Set(sections.map(\.rawValue))
    return entries.filter { allowed.contains($0.section) }.sorted { $0.stableId < $1.stableId }

}

public func rgSettingsController(context: AccountContext, page: RGSettingsPage = .home, initialSearchQuery: String? = nil, focusSetting: String? = nil) -> ViewController {
    // MARK: Regram — legacy root links open the single Pro hub; transcription has one editor.
    if page == .home { return context.sharedContext.makeRGProController(context: context) }
    if page == .transcription { return rgSTTSettingsController(context: context) }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
//    var getRootControllerImpl: (() -> UIViewController?)?
//    var getNavigationControllerImpl: (() -> NavigationController?)?
    var askForRestart: (() -> Void)?
    
    let initialState = RGSettingsControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    
//    let sliderPromise = ValuePromise(RGSimpleSettings.shared.accountColorsSaturation, ignoreRepeated: true)
//    let sliderStateValue = Atomic(value: RGSimpleSettings.shared.accountColorsSaturation)
//    let _: ((Int32) -> Int32) -> Void = { f in
//        sliderPromise.set(sliderStateValue.modify( {f($0)}))
//    }
    
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    let startupFolders = Atomic<[ChatListFilter]>(value: [])
    
    let arguments = RGItemListArguments<RGBoolSetting, RGSliderSetting, RGOneFromManySetting, RGDisclosureLink, AnyHashable>(
        context: context,
        /*updatePeerColor: { color in
          updateState { state in
              var updatedState = state
              updatedState.updatedNameColor = color
              return updatedState
          }
        },*/ setBoolValue: { setting, value in
        switch setting {
        case .showFoldersInShareSheet: RGSimpleSettings.shared.showFoldersInShareSheet = value
        case .tapMessageRowToOpenContextMenu: RGSimpleSettings.shared.tapMessageRowToOpenContextMenu = value
        case .confirmUnpin: RGSimpleSettings.shared.confirmUnpin = value
        case .hideSavedAndArchivedMessagesInList: RGSimpleSettings.shared.hideSavedAndArchivedMessagesInList = value
        case .hidePrivateChatActivities: RGSimpleSettings.shared.hidePrivateChatActivities = value
        case .hideFolderUnreadCount: RGSimpleSettings.shared.hideFolderUnreadCount = value
        case .showArchiveInFolders: RGSimpleSettings.shared.showArchiveInFolders = value
        case .openArchiveOnPull: RGSimpleSettings.shared.openArchiveOnPull = value
        case .stayAtLatestMessageAfterRefresh: RGSimpleSettings.shared.stayAtLatestMessageAfterRefresh = value
        case .hideTopStories: RGSimpleSettings.shared.hideTopStories = value
        case .disableChatAvatarStories: RGSimpleSettings.shared.disableChatAvatarStories = value
        case .hideTabBarPermissionWarnings: RGSimpleSettings.shared.hideTabBarPermissionWarnings = value
        case .disableCommunityChatGrouping: RGSimpleSettings.shared.disableCommunityChatGrouping = value
        case .bottomUpGlobalSearchResults: RGSimpleSettings.shared.bottomUpGlobalSearchResults = value
        case .keepNewChatsVisibleAtTop: RGSimpleSettings.shared.keepNewChatsVisibleAtTop = value

        case .hideChatListSeparators:
            RGSimpleSettings.shared.hideChatListSeparators = value
            NotificationCenter.default.post(name: RGSimpleSettings.chatListSeparatorSettingsDidChange, object: nil)
        case .hidePhoneInSettings:
            RGSimpleSettings.shared.hidePhoneInSettings = value
            askForRestart?()
        case .showTabNames:
            RGSimpleSettings.shared.showTabNames = value
        case .showContactsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowContactsTab(value) }
                )
            ).start()
        case .showCallsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowTab(value) }
                )
            ).start()
        case .foldersAtBottom:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.foldersTabAtBottom = value
                        return settings
                    }
                )
            ).start()
        case .startTelescopeWithRearCam:
            RGSimpleSettings.shared.startTelescopeWithRearCam = value
        case .hideStories:
            RGSimpleSettings.shared.hideStories = value
        case .showProfileId:
            RGSimpleSettings.shared.showProfileId = value
        case .warnOnStoriesOpen:
            RGSimpleSettings.shared.warnOnStoriesOpen = value
        case .sendWithReturnKey:
            RGSimpleSettings.shared.sendWithReturnKey = value
        case .chooseFolderAfterJoining:
            RGSimpleSettings.shared.chooseFolderAfterJoining = value
        case .sendLargePhotos:
            RGSimpleSettings.shared.sendLargePhotos = value
        case .storyStealthMode:
            RGSimpleSettings.shared.storyStealthMode = value
        case .disableSwipeToRecordStory:
            RGSimpleSettings.shared.disableSwipeToRecordStory = value
        case .quickTranslateButton:
            RGSimpleSettings.shared.quickTranslateButton = value
        case .downloadSpeedBoost:
            RGSimpleSettings.shared.downloadSpeedBoost = value ? RGSimpleSettings.DownloadSpeedBoostValues.enabled.rawValue : RGSimpleSettings.DownloadSpeedBoostValues.none.rawValue
            let _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { settings in
                var settings = settings
                settings.useExperimentalDownload = value
                return settings
            }).start(completed: { Queue.mainQueue().async { askForRestart?() } })
        case .uploadSpeedBoost:
            RGSimpleSettings.shared.uploadSpeedBoost = value
        case .mediaLoadingExperiment:
            RGSimpleSettings.shared.mediaLoadingExperiment = value
        case .showMediaMetadata:
            RGSimpleSettings.shared.showMediaMetadata = value
        case .hideReactions:
            RGSimpleSettings.shared.hideReactions = value
        case .showRepostToStory:
            RGSimpleSettings.shared.showRepostToStoryV2 = value
        case .contextShowSelectFromUser:
            RGSimpleSettings.shared.contextShowSelectFromUser = value
        case .contextShowSaveToCloud:
            RGSimpleSettings.shared.contextShowSaveToCloud = value
        case .contextShowRestrict:
            RGSimpleSettings.shared.contextShowRestrict = value
        case .contextShowHideForwardName:
            RGSimpleSettings.shared.contextShowHideForwardName = value
        case .disableScrollToNextChannel:
            RGSimpleSettings.shared.disableScrollToNextChannel = !value
        case .disableScrollToNextTopic:
            RGSimpleSettings.shared.disableScrollToNextTopic = !value
        case .disableChatSwipeOptions:
            RGSimpleSettings.shared.disableChatSwipeOptions = !value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .disableDeleteChatSwipeOption:
            RGSimpleSettings.shared.disableDeleteChatSwipeOption = !value
            askForRestart?()
        case .disableGalleryCamera:
            RGSimpleSettings.shared.disableGalleryCamera = !value
            simplePromise.set(true)
        case .disableGalleryCameraPreview:
            RGSimpleSettings.shared.disableGalleryCameraPreview = !value
        case .disableSendAsButton:
            RGSimpleSettings.shared.disableSendAsButton = !value
        case .disableSnapDeletionEffect:
            RGSimpleSettings.shared.disableSnapDeletionEffect = !value
        case .contextShowReport:
            RGSimpleSettings.shared.contextShowReport = value
        case .contextShowReply:
            RGSimpleSettings.shared.contextShowReply = value
        case .contextShowPin:
            RGSimpleSettings.shared.contextShowPin = value
        case .contextShowSaveMedia:
            RGSimpleSettings.shared.contextShowSaveMedia = value
        case .contextShowMessageReplies:
            RGSimpleSettings.shared.contextShowMessageReplies = value
        case .stickerTimestamp:
            RGSimpleSettings.shared.stickerTimestamp = value
        case .contextShowJson:
            RGSimpleSettings.shared.contextShowJson = value
        // MARK: Regram — the contextShow* cases above are no longer reachable from this screen; the
        // switches live in `rgContextMenuOrderController`, which writes the same settings directly.
        // They are kept so a stored search/deeplink referring to one still resolves.
        case .profileDefaultTabGroupsInCommon:
            RGSimpleSettings.shared.profileDefaultTabGroupsInCommon = value
        case .hideRecordingButton:
            RGSimpleSettings.shared.hideRecordingButton = !value
        case .hideTabBar:
            RGSimpleSettings.shared.hideTabBar = value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .showDC:
            RGSimpleSettings.shared.showDC = value
        case .showCreationDate:
            RGSimpleSettings.shared.showCreationDate = value
        case .showRegDate:
            RGSimpleSettings.shared.showRegDate = value
        case .compactChatList:
            RGSimpleSettings.shared.compactChatList = value
            askForRestart?()
        case .unlimitedPinnedChats:
            RGSimpleSettings.shared.unlimitedPinnedChats = value
        case .showMessageId:
            RGSimpleSettings.shared.showMessageId = value
        case .automaticallyRevealSpoilers:
            RGSimpleSettings.shared.automaticallyRevealSpoilers = value
        case .showForwardedMessageDate:
            RGSimpleSettings.shared.showForwardedMessageDate = value
        case .compactFolderNames:
            RGSimpleSettings.shared.compactFolderNames = value
            askForRestart?()
        case .allChatsHidden:
            RGSimpleSettings.shared.allChatsHidden = value
            askForRestart?()
        case .defaultEmojisFirst:
            RGSimpleSettings.shared.defaultEmojisFirst = value
        case .messageDoubleTapActionOutgoingEdit:
            RGSimpleSettings.shared.messageDoubleTapActionOutgoing = value ? RGSimpleSettings.MessageDoubleTapAction.edit.rawValue : RGSimpleSettings.MessageDoubleTapAction.default.rawValue
        case .wideChannelPosts:
            RGSimpleSettings.shared.wideChannelPosts = value
        case .forceEmojiTab:
            RGSimpleSettings.shared.forceEmojiTab = value
        case .forceBuiltInMic:
            RGSimpleSettings.shared.forceBuiltInMic = value
        case .hideChannelBottomButton:
            RGSimpleSettings.shared.hideChannelBottomButton = !value
        case .secondsInMessages:
            RGSimpleSettings.shared.secondsInMessages = value
        case .confirmCalls:
            RGSimpleSettings.shared.confirmCalls = value
        case .enableVoipTcp:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.enableVoipTcp = value
                        return settings
                    }
                )
            ).start()
        case .nyStyleSnow:
            RGSimpleSettings.shared.nyStyle = value ? RGSimpleSettings.NYStyle.snow.rawValue : RGSimpleSettings.NYStyle.default.rawValue
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .nyStyleLightning:
            RGSimpleSettings.shared.nyStyle = value ? RGSimpleSettings.NYStyle.lightning.rawValue : RGSimpleSettings.NYStyle.default.rawValue
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        }
    }, updateSliderValue: { setting, value in
        switch (setting) {
            case .accountColorsSaturation:
                if RGSimpleSettings.shared.accountColorsSaturation != value {
                    RGSimpleSettings.shared.accountColorsSaturation = value
                    simplePromise.set(true)
                }
            case .outgoingPhotoQuality:
                if RGSimpleSettings.shared.outgoingPhotoQuality != value {
                    RGSimpleSettings.shared.outgoingPhotoQuality = value
                    simplePromise.set(true)
                }
            case .stickerSize:
                if RGSimpleSettings.shared.stickerSize != value {
                    RGSimpleSettings.shared.stickerSize = value
                    simplePromise.set(true)
                }
        }

    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .chatListLines:
                for count in RGSimpleSettings.ChatListLines.allCases.reversed() {
                    items.append(ActionSheetButtonItem(title: "Settings.ChatList.Lines.\(count.rawValue)".i18n(presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.chatListLines = count.rawValue
                        simplePromise.set(true)
                        askForRestart?()
                    }))
                }
            case .messageDoubleTapAction, .messageDoubleTapActionWithoutEditPermission:
                let isOverride = setting == .messageDoubleTapActionWithoutEditPermission
                var values = RGSimpleSettings.MessageDoubleTapActionV2.allCases.map(\.rawValue)
                if isOverride {
                    values.insert(RGSimpleSettings.messageDoubleTapSameAsUnified, at: 0)
                }
                for value in values {
                    items.append(ActionSheetButtonItem(title: "DoubleTap.Action.\(value)".i18n(presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        if isOverride {
                            RGSimpleSettings.shared.messageDoubleTapActionWithoutEditPermission = value
                        } else {
                            RGSimpleSettings.shared.messageDoubleTapAction = value
                        }
                        simplePromise.set(true)
                    }))
                }
            case .recentStickerLimit:
                for limit in RGSimpleSettings.recentStickerLimitOptions {
                    items.append(ActionSheetButtonItem(title: String(limit), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.recentStickerLimit = limit
                        simplePromise.set(true)
                        let _ = context.account.postbox.transaction { transaction -> Void in
                            let recent = transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudRecentStickers)
                            if recent.count > Int(limit) {
                                transaction.replaceOrderedItemListItems(collectionId: Namespaces.OrderedItemList.CloudRecentStickers, items: Array(recent.prefix(Int(limit))))
                            }
                        }.startStandalone()
                    }))
                }
            case .defaultVideoQuality:
                let lang = presentationData.strings.primaryComponent.languageCode
                for preference in RGVideoQualityPreference.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.DefaultVideoQuality.\(preference.rawValue)", lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.defaultVideoQuality = preference.rawValue
                        simplePromise.set(true)
                    }))
                }
            case .allChatsTitleLengthOverride:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.allChatsTitleLengthOverride = value
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.AllChatsTitleLengthOverride.allCases {
                    let title: String
                    switch (value) {
                        case RGSimpleSettings.AllChatsTitleLengthOverride.short:
                            title = "\"\(presentationData.strings.ChatList_Tabs_All)\""
                        case RGSimpleSettings.AllChatsTitleLengthOverride.long:
                            title = "\"\(presentationData.strings.ChatList_Tabs_AllChats)\""
                        default:
                            title = i18n("Settings.Folders.AllChatsTitle.none", presentationData.strings.rgLanguageCode)
                    }
                    items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
//        case .allChatsFolderPositionOverride:
//            let setAction: (String) -> Void = { value in
//                RGSimpleSettings.shared.allChatsFolderPositionOverride = value
//                simplePromise.set(true)
//            }
//
//            for value in RGSimpleSettings.AllChatsFolderPositionOverride.allCases {
//                items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.AllChatsTitle.\(value)", presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
//                    actionSheet?.dismissAnimated()
//                    setAction(value.rawValue)
//                }))
//            }
            case .chatListSwipeAction:
                for value in ["both", "switch", "quick", "none"] {
                    items.append(ActionSheetButtonItem(title: ("features.ChatListSwipeAction." + value).i18n(presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.chatListSwipeAction = value
                        simplePromise.set(true)
                    }))
                }
            case .startupFolder:
                items = rgStartupFolderActionItems(filters: startupFolders.with { $0 }, accountId: context.account.peerId.toInt64(), presentationData: presentationData, dismiss: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                }, updated: { simplePromise.set(true) })
            case .chatListFolderTabDisplayMode:
                for value in ["text", "icon", "both"] {
                    items.append(ActionSheetButtonItem(title: ("features.ChatListFolderTabDisplayMode." + value).i18n(presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.chatListFolderTabDisplayMode = value
                        simplePromise.set(true)
                    }))
                }
            case .communityAvatarTapAction:
                for value in ["chat", "community", "arrow"] {
                    items.append(ActionSheetButtonItem(title: ("features.CommunityAvatarTapAction." + value).i18n(presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.communityAvatarTapAction = value
                        simplePromise.set(true)
                    }))
                }
            case .videoPIPSwipeDirection:
                for value in ["up", "none"] {
                    items.append(ActionSheetButtonItem(title: ("features.VideoPIPSwipeDirection." + value).i18n(presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.videoPIPSwipeDirection = value
                        simplePromise.set(true)
                    }))
                }

            case .translationBackend:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.translationBackend = value
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.TranslationBackend.allCases {
                    if value == .system {
                        if #available(iOS 18.0, *) {
                        } else {
                            continue // System translation is not available on iOS 17 and below
                        }
                    }
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Translation.Backend.\(value.rawValue)", presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .nyStyle:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.nyStyle = value
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.NYStyle.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.NY.Style.\(value.rawValue)", presentationData.strings.rgLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { [context] link in
        switch (link) {

            case .inlineBotRules: pushControllerImpl?(rgFeatureInlineBotRulesController(context: context))
            case .groupProfileSettings: pushControllerImpl?(rgFeatureGroupProfileSettingsController(context: context))
            case .textStyleMenu: pushControllerImpl?(rgFeatureTextStyleMenuSettingsController(context: context))
            case .llmTranslationSettings:
                pushControllerImpl?(rgLLMTranslationSettingsController(context: context))
            case .languageSettings:
                pushControllerImpl?(context.sharedContext.makeLocalizationListController(context: context))
            case .contentSettings:
                let _ = (getRGSettingsURL(context: context) |> deliverOnMainQueue).start(next: { [weak context] url in
                    guard let strongContext = context else {
                        return
                    }
                    strongContext.sharedContext.applicationBindings.openUrl(url)
                })
            // MARK: Regram
            case .contextMenuOrder:
                pushControllerImpl?(rgContextMenuOrderController(context: context))
            case .bottomBarLayout:
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                pushControllerImpl?(rgBottomBarSettingsController(context: context))
        }
    }, settingsPage: "settings." + page.rawValue)
    
    let sharedData = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
    let preferences = context.account.postbox.preferencesView(keys: [PreferencesKeys.appConfiguration])
    let updatedContentSettingsConfiguration = contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)
    let contentSettingsConfiguration = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfiguration.set(.single(nil)
    |> then(updatedContentSettingsConfiguration))
    
    let signal = combineLatest(simplePromise.get(), /*sliderPromise.get(),*/ statePromise.get(), context.sharedContext.presentationData, sharedData, preferences, contentSettingsConfiguration.get(),
        context.engine.accountData.observeAvailableColorOptions(scope: .replies),
        context.engine.accountData.observeAvailableColorOptions(scope: .profile),
        page == .folders ? context.engine.peers.updatedChatListFilters() : .single([])
    )
    |> map { _, /*sliderValue,*/ state, presentationData, sharedData, view, contentSettingsConfiguration, availableReplyColors, availableProfileColors, filters ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let appConfiguration: AppConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        let callListSettings: CallListSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
        let experimentalUISettings: ExperimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
        
        _ = startupFolders.swap(filters)
        let startupFolderTitle = rgStartupFolderTitle(filters: filters, accountId: context.account.peerId.toInt64(), presentationData: presentationData)
        let entries = RGControllerEntries(presentationData: presentationData, callListSettings: callListSettings, experimentalUISettings: experimentalUISettings, appConfiguration: appConfiguration, nameColors: PeerNameColors.with(availableReplyColors: availableReplyColors, availableProfileColors: availableProfileColors), state: state, page: page, startupFolderTitle: startupFolderTitle)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(page == .home ? "Regram" : page.titleKey.i18n(presentationData.strings.rgLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        // TODO(regram): focusOnItemTag support
        /* var index = 0
        var scrollToItem: ListViewScrollToItem?
         if let focusOnItemTag = focusOnItemTag {
            for entry in entries {
                if entry.tag?.isEqual(to: focusOnItemTag) ?? false {
                    scrollToItem = ListViewScrollToItem(index: index, position: .top(0.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Up)
                }
                index += 1
            }
        } */
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: rgSettingsScrollTarget(entries, item: focusSetting), animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = RGSettingsListController(context: context, state: signal)
    controller.focusSetting = focusSetting
    controller.focusColor = context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemAccentColor
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
//    getRootControllerImpl = { [weak controller] in
//        return controller?.view.window?.rootViewController
//    }
//    getNavigationControllerImpl = { [weak controller] in
//        return controller?.navigationController as? NavigationController
//    }
    askForRestart = { [weak context] in
        guard let context = context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(
            UndoOverlayController(
                presentationData: presentationData, 
                content: .info(title: nil, // i18n("Common.RestartRequired", presentationData.strings.rgLanguageCode),
                    text: i18n("Common.RestartRequired", presentationData.strings.rgLanguageCode),
                    timeout: nil,
                    customUndoText: i18n("Common.RestartNow", presentationData.strings.rgLanguageCode) //presentationData.strings.Common_Yes
                ),
                elevatedLayout: false,
                action: { action in if action == .undo { exit(0) }; return true }
            ),
            nil
        )
    }
    return controller

}

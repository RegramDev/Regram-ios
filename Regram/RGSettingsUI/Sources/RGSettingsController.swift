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

private enum RGControllerSection: Int32, RGItemListSection {
    case search
    case trending
    case content
    case tabs
    case folders
    case chatList
    case profiles
    case stories
    case translation
    case voiceMessages
    case calls
    case photo
    case stickers
    case videoNotes
    case contextMenu
    case accountColors
    case other
}

private enum RGBoolSetting: String {
    case hidePhoneInSettings
    case showTabNames
    case showContactsTab
    case showCallsTab
    case wideTabBar
    case foldersAtBottom
    case startTelescopeWithRearCam
    case hideStories
    case uploadSpeedBoost
    case showProfileId
    case warnOnStoriesOpen
    case sendWithReturnKey
    case rememberLastFolder
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
    case compactMessagePreview
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
    case swipeForVideoPIP
    case enableVoipTcp
    case nyStyleSnow
    case nyStyleLightning
    case tabBarSearchEnabled
}

private enum RGOneFromManySetting: String {
    case nyStyle
    case bottomTabStyle
    case downloadSpeedBoost
    case allChatsTitleLengthOverride
//    case allChatsFolderPositionOverride
    case translationBackend
    case transcriptionBackend
}

private enum RGSliderSetting: String {
    case accountColorsSaturation
    case outgoingPhotoQuality
    case stickerSize
}

private enum RGDisclosureLink: String {
    case contentSettings
    case languageSettings
    // MARK: Regram
    case contextMenuOrder
}

private struct PeerNameColorScreenState: Equatable {
    var updatedNameColor: PeerNameColor?
    var updatedBackgroundEmojiId: Int64?
}

private struct RGSettingsControllerState: Equatable {
    var searchQuery: String?
}

private typealias RGControllerEntry = RGItemListUIEntry<RGControllerSection, RGBoolSetting, RGSliderSetting, RGOneFromManySetting, RGDisclosureLink, AnyHashable>

private func RGControllerEntries(presentationData: PresentationData, callListSettings: CallListSettings, experimentalUISettings: ExperimentalUISettings, appConfiguration: AppConfiguration, nameColors: PeerNameColors, state: RGSettingsControllerState) -> [RGControllerEntry] {
    
    let lang = presentationData.strings.baseLanguageCode
    let strings = presentationData.strings
    let newStr = strings.Settings_New
    var entries: [RGControllerEntry] = []
    
    let id = RGItemListCounter()
    
    entries.append(.searchInput(id: id.count, section: .search, title: NSAttributedString(string: "🔍"), text: state.searchQuery ?? "", placeholder: strings.Common_Search))
    
    
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
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .hideTabBar, value: RGSimpleSettings.shared.hideTabBar, text: i18n("Settings.Tabs.HideTabBar", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showContactsTab, value: callListSettings.showContactsTab, text: i18n("Settings.Tabs.ShowContacts", lang), enabled: !RGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showCallsTab, value: callListSettings.showTab, text: strings.CallSettings_TabIcon, enabled: !RGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showTabNames, value: RGSimpleSettings.shared.showTabNames, text: i18n("Settings.Tabs.ShowNames", lang), enabled: !RGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .tabBarSearchEnabled, value: RGSimpleSettings.shared.tabBarSearchEnabled, text: i18n("Settings.Tabs.SearchButton", lang), enabled: !RGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .wideTabBar, value: RGSimpleSettings.shared.wideTabBar, text: i18n("Settings.Tabs.WideTabBar", lang), enabled: !RGSimpleSettings.shared.hideTabBar))
    entries.append(.notice(id: id.count, section: .tabs, text: i18n("Settings.Tabs.WideTabBar.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .folders, text: strings.Settings_ChatFolders.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .foldersAtBottom, value: experimentalUISettings.foldersTabAtBottom, text: i18n("Settings.Folders.BottomTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .allChatsHidden, value: RGSimpleSettings.shared.allChatsHidden, text: i18n("Settings.Folders.AllChatsHidden", lang, strings.ChatList_Tabs_AllChats), enabled: true))
    #if DEBUG
//    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsFolderPositionOverride, text: i18n("Settings.Folders.AllChatsPlacement", lang), value: i18n("Settings.Folders.AllChatsPlacement.\(RGSimpleSettings.shared.allChatsFolderPositionOverride)", lang), enabled: true))
    #endif
    entries.append(.toggle(id: id.count, section: .folders, settingName: .compactFolderNames, value: RGSimpleSettings.shared.compactFolderNames, text: i18n("Settings.Folders.CompactNames", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsTitleLengthOverride, text: i18n("Settings.Folders.AllChatsTitle", lang), value: i18n("Settings.Folders.AllChatsTitle.\(RGSimpleSettings.shared.allChatsTitleLengthOverride)", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .rememberLastFolder, value: RGSimpleSettings.shared.rememberLastFolder, text: i18n("Settings.Folders.RememberLast", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .folders, text: i18n("Settings.Folders.RememberLast.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .chatList, text: i18n("Settings.ChatList.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactChatList, value: RGSimpleSettings.shared.compactChatList, text: i18n("Settings.CompactChatList", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactMessagePreview, value: RGSimpleSettings.shared.chatListLines != RGSimpleSettings.ChatListLines.three.rawValue, text: i18n("Settings.CompactMessagePreview", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableChatSwipeOptions, value: !RGSimpleSettings.shared.disableChatSwipeOptions, text: i18n("Settings.ChatSwipeOptions", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableDeleteChatSwipeOption, value: !RGSimpleSettings.shared.disableDeleteChatSwipeOption, text: i18n("Settings.DeleteChatSwipeOption", lang), enabled: !RGSimpleSettings.shared.disableChatSwipeOptions))
    
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
    entries.append(.oneFromManySelector(id: id.count, section: .translation, settingName: .translationBackend, text: i18n("Settings.Translation.Backend", lang), value: i18n("Settings.Translation.Backend.\(RGSimpleSettings.shared.translationBackend)", lang), enabled: true))
    if !RGSimpleSettings.shared.translationBackendIsExternal {
        entries.append(.notice(id: id.count, section: .translation, text: i18n("Settings.Translation.Backend.Notice", lang, "Settings.Translation.Backend.\(RGSimpleSettings.TranslationBackend.gtranslate.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.toggle(id: id.count, section: .translation, settingName: .quickTranslateButton, value: RGSimpleSettings.shared.quickTranslateButton, text: i18n("Settings.Translation.QuickTranslateButton", lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .translation, link: .languageSettings, text: strings.Localization_TranslateEntireChat))
    entries.append(.notice(id: id.count, section: .translation, text: i18n("Common.NoTelegramPremiumNeeded", lang, strings.Settings_Premium)))

    entries.append(.header(id: id.count, section: .voiceMessages, text: "Settings.Transcription.Header".i18n(lang), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .voiceMessages, settingName: .transcriptionBackend, text: i18n("Settings.Transcription.Backend", lang), value: i18n("Settings.Transcription.Backend.\(RGSimpleSettings.shared.transcriptionBackend)", lang), enabled: true))
    if RGSimpleSettings.shared.transcriptionBackendEnum != .apple {
        entries.append(.notice(id: id.count, section: .voiceMessages, text: i18n("Settings.Transcription.Backend.Notice", lang, "Settings.Transcription.Backend.\(RGSimpleSettings.TranscriptionBackend.apple.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.header(id: id.count, section: .voiceMessages, text: strings.Privacy_VoiceMessages.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .voiceMessages, settingName: .forceBuiltInMic, value: RGSimpleSettings.shared.forceBuiltInMic, text: i18n("Settings.forceBuiltInMic", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .voiceMessages, text: i18n("Settings.forceBuiltInMic.Notice", lang)))

    entries.append(.header(id: id.count, section: .calls, text: strings.Calls_TabTitle.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .calls, settingName: .enableVoipTcp, value: experimentalUISettings.enableVoipTcp, text: "Force TCP", enabled: true))
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
    entries.append(.header(id: id.count, section: .other, text: strings.Appearance_Other.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .other, settingName: .swipeForVideoPIP, value: RGSimpleSettings.shared.videoPIPSwipeDirection == RGSimpleSettings.VideoPIPSwipeDirection.up.rawValue, text: i18n("Settings.swipeForVideoPIP", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.swipeForVideoPIP.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideChannelBottomButton, value: !RGSimpleSettings.shared.hideChannelBottomButton, text: i18n("Settings.showChannelBottomButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .wideChannelPosts, value: RGSimpleSettings.shared.wideChannelPosts, text: i18n("Settings.wideChannelPosts", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .secondsInMessages, value: RGSimpleSettings.shared.secondsInMessages, text: i18n("Settings.secondsInMessages", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .messageDoubleTapActionOutgoingEdit, value: RGSimpleSettings.shared.messageDoubleTapActionOutgoing == RGSimpleSettings.MessageDoubleTapAction.edit.rawValue, text: i18n("Settings.messageDoubleTapActionOutgoingEdit", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideRecordingButton, value: !RGSimpleSettings.shared.hideRecordingButton, text: i18n("Settings.RecordingButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSnapDeletionEffect, value: !RGSimpleSettings.shared.disableSnapDeletionEffect, text: i18n("Settings.SnapDeletionEffect", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSendAsButton, value: !RGSimpleSettings.shared.disableSendAsButton, text: i18n("Settings.SendAsButton", lang, strings.Conversation_SendMesageAs), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCamera, value: !RGSimpleSettings.shared.disableGalleryCamera, text: i18n("Settings.GalleryCamera", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCameraPreview, value: !RGSimpleSettings.shared.disableGalleryCameraPreview, text: i18n("Settings.GalleryCameraPreview", lang), enabled: !RGSimpleSettings.shared.disableGalleryCamera))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextChannel, value: !RGSimpleSettings.shared.disableScrollToNextChannel, text: i18n("Settings.PullToNextChannel", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextTopic, value: !RGSimpleSettings.shared.disableScrollToNextTopic, text: i18n("Settings.PullToNextTopic", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideReactions, value: RGSimpleSettings.shared.hideReactions, text: i18n("Settings.HideReactions", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .uploadSpeedBoost, value: RGSimpleSettings.shared.uploadSpeedBoost, text: i18n("Settings.UploadsBoost", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .other, settingName: .downloadSpeedBoost, text: i18n("Settings.DownloadsBoost", lang), value: i18n("Settings.DownloadsBoost.\(RGSimpleSettings.shared.downloadSpeedBoost)", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.DownloadsBoost.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .sendWithReturnKey, value: RGSimpleSettings.shared.sendWithReturnKey, text: i18n("Settings.SendWithReturnKey", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .forceEmojiTab, value: RGSimpleSettings.shared.forceEmojiTab, text: i18n("Settings.ForceEmojiTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .defaultEmojisFirst, value: RGSimpleSettings.shared.defaultEmojisFirst, text: i18n("Settings.DefaultEmojisFirst", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.DefaultEmojisFirst.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hidePhoneInSettings, value: RGSimpleSettings.shared.hidePhoneInSettings, text: i18n("Settings.HidePhoneInSettingsUI", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.HidePhoneInSettingsUI.Notice", lang)))
    
    return filterRGItemListUIEntrires(entries: entries, by: state.searchQuery)
}

public func rgSettingsController(context: AccountContext/*, focusOnItemTag: Int? = nil*/) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
//    var getRootControllerImpl: (() -> UIViewController?)?
//    var getNavigationControllerImpl: (() -> NavigationController?)?
    var askForRestart: (() -> Void)?
    
    let initialState = RGSettingsControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((RGSettingsControllerState) -> RGSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
//    let sliderPromise = ValuePromise(RGSimpleSettings.shared.accountColorsSaturation, ignoreRepeated: true)
//    let sliderStateValue = Atomic(value: RGSimpleSettings.shared.accountColorsSaturation)
//    let _: ((Int32) -> Int32) -> Void = { f in
//        sliderPromise.set(sliderStateValue.modify( {f($0)}))
//    }
    
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
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
        case .hidePhoneInSettings:
            RGSimpleSettings.shared.hidePhoneInSettings = value
            askForRestart?()
        case .showTabNames:
            RGSimpleSettings.shared.showTabNames = value
            askForRestart?()
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
        case .tabBarSearchEnabled:
            RGSimpleSettings.shared.tabBarSearchEnabled = value
        case .wideTabBar:
            RGSimpleSettings.shared.wideTabBar = value
            askForRestart?()
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
        case .rememberLastFolder:
            RGSimpleSettings.shared.rememberLastFolder = value
        case .sendLargePhotos:
            RGSimpleSettings.shared.sendLargePhotos = value
        case .storyStealthMode:
            RGSimpleSettings.shared.storyStealthMode = value
        case .disableSwipeToRecordStory:
            RGSimpleSettings.shared.disableSwipeToRecordStory = value
        case .quickTranslateButton:
            RGSimpleSettings.shared.quickTranslateButton = value
        case .uploadSpeedBoost:
            RGSimpleSettings.shared.uploadSpeedBoost = value
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
        case .compactMessagePreview:
            RGSimpleSettings.shared.chatListLines = value ? RGSimpleSettings.ChatListLines.one.rawValue : RGSimpleSettings.ChatListLines.three.rawValue
            askForRestart?()
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
        case .swipeForVideoPIP:
            RGSimpleSettings.shared.videoPIPSwipeDirection = value ? RGSimpleSettings.VideoPIPSwipeDirection.up.rawValue : RGSimpleSettings.VideoPIPSwipeDirection.none.rawValue
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
            case .downloadSpeedBoost:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.downloadSpeedBoost = value
                    
                    let enableDownloadX: Bool
                    switch (value) {
                        case RGSimpleSettings.DownloadSpeedBoostValues.none.rawValue:
                            enableDownloadX = false
                        default:
                            enableDownloadX = true
                    }
                    
                    // Updating controller
                    simplePromise.set(true)

                    let _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { settings in
                        var settings = settings
                        settings.useExperimentalDownload = enableDownloadX
                        return settings
                    }).start(completed: {
                        Queue.mainQueue().async {
                            askForRestart?()
                        }
                    })
                }

                for value in RGSimpleSettings.DownloadSpeedBoostValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.DownloadsBoost.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .bottomTabStyle:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.bottomTabStyle = value
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.BottomTabStyleValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.BottomTabStyle.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
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
                            title = i18n("Settings.Folders.AllChatsTitle.none", presentationData.strings.baseLanguageCode)
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
//                items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.AllChatsTitle.\(value)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
//                    actionSheet?.dismissAnimated()
//                    setAction(value.rawValue)
//                }))
//            }
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
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Translation.Backend.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .transcriptionBackend:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.transcriptionBackend = value
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.TranscriptionBackend.allCases {
                    if #available(iOS 13.0, *) {
                    } else {
                        if value == .apple {
                            continue // Apple recognition is not available on iOS 12
                        }
                    }
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Transcription.Backend.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
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
                    items.append(ActionSheetButtonItem(title: i18n("Settings.NY.Style.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
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
    }, openDisclosureLink: { link in
        switch (link) {
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
        }
    }, searchInput: { searchQuery in
        updateState { state in
            var updatedState = state
            updatedState.searchQuery = searchQuery
            return updatedState
        }
    })
    
    let sharedData = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
    let preferences = context.account.postbox.preferencesView(keys: [PreferencesKeys.appConfiguration])
    let updatedContentSettingsConfiguration = contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)
    let contentSettingsConfiguration = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfiguration.set(.single(nil)
    |> then(updatedContentSettingsConfiguration))
    
    let signal = combineLatest(simplePromise.get(), /*sliderPromise.get(),*/ statePromise.get(), context.sharedContext.presentationData, sharedData, preferences, contentSettingsConfiguration.get(),
        context.engine.accountData.observeAvailableColorOptions(scope: .replies),
        context.engine.accountData.observeAvailableColorOptions(scope: .profile)
    )
    |> map { _, /*sliderValue,*/ state, presentationData, sharedData, view, contentSettingsConfiguration, availableReplyColors, availableProfileColors ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let appConfiguration: AppConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        let callListSettings: CallListSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
        let experimentalUISettings: ExperimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
        
        let entries = RGControllerEntries(presentationData: presentationData, callListSettings: callListSettings, experimentalUISettings: experimentalUISettings, appConfiguration: appConfiguration, nameColors: PeerNameColors.with(availableReplyColors: availableReplyColors, availableProfileColors: availableProfileColors), state: state)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Regram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
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
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
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
                content: .info(title: nil, // i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode),
                    text: i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode),
                    timeout: nil,
                    customUndoText: i18n("Common.RestartNow", presentationData.strings.baseLanguageCode) //presentationData.strings.Common_Yes
                ),
                elevatedLayout: false,
                action: { action in if action == .undo { exit(0) }; return true }
            ),
            nil
        )
    }
    return controller

}

// MARK: Regram — one resolver serves global search and copied setting links.
import AccountContext
import Display
import RGSettingsUI
import RGSimpleSettings
import RGStrings
import SettingsUI

public func rgControllerForSettingsLink(context: AccountContext, destination: RGSettingsDestination) -> ViewController? {
    let focus = destination.item
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    // Disclosure entries open their existing destination, keeping one settings route per feature.
    let disclosed: [String: String] = [
        "messagesPage": "pro.messages", "inputPage": "pro.input", "networkPage": "pro.network", "translationPage": "pro.translation", "privacyPage": "pro.privacy", "mediaPage": "pro.media", "appearancePage": "pro.appearance", "notificationsPage": "pro.notifications", "toolsPage": "pro.tools",
        "messageActionsSettings": "settings.messageActions", "chatListSettings": "settings.chatList", "folderSettings": "settings.folders", "translationSettings": "settings.translation", "transcriptionSettings": "stt", "photoSettings": "settings.photos", "stickerSettings": "settings.stickers", "recordingSettings": "settings.recording", "mediaSettings": "settings.media", "appearanceSettings": "settings.appearance", "profileSettings": "settings.profiles", "storiesSettings": "settings.stories", "appSettings": "settings.app",
        "inputSettings": "settings.input", "transferSettings": "settings.transfer", "privacySettings": "settings.privacy", "bookmarks": "bookmarks",
        "summarySettings": "summary", "networkPolicy": "networkPolicy", "llmTranslationSettings": "llm", "bottomBarLayout": "bottomBar", "contextMenuOrder": "contextMenu", "linkPreviewSettings": "linkPreview", "antiFeatures": "antiFeatures", "ghostMode": "ghostMode", "messageFilter": "messageFilter", "hiddenUsers": "hiddenUsers", "antiRevokeChats": "antiRevokeChats", "fonts": "fonts", "backup": "backup", "chatPreferences": "chatPreferences", "revokedMessages": "revokedMessages", "diagnostics": "diagnostics", "appIcons": "appIcons", "appBages": "appBadges"
    ]
    if destination.page.hasPrefix("pro.") || destination.page.hasPrefix("settings."), let focus, let page = disclosed[focus], let target = RGSettingsDestination(page: page) {
        return rgControllerForSettingsLink(context: context, destination: target)
    }
    if destination.page.hasPrefix("pro."), let page = RGProSettingsPage(rawValue: String(destination.page.dropFirst(4))) { return rgProController(context: context, page: page, focusSetting: focus) }
    if destination.page.hasPrefix("settings."), let page = RGSettingsPage(rawValue: String(destination.page.dropFirst(9))) { return rgSettingsController(context: context, page: page, focusSetting: focus) }
    switch destination.page {
    case "bottomBar": return rgBottomBarSettingsController(context: context, focusSetting: focus)
    case "summary": return rgLLMSummarySettingsController(context: context, focusSetting: focus)
    case "networkPolicy":
        if focus == "test" { return rgDNSDiagnosticsController(context: context, policy: RGSimpleSettings.shared.networkPolicy) }
        return rgNetworkPolicyController(context: context, focusSetting: focus)
    case "llm": return rgLLMTranslationSettingsController(context: context, focusSetting: focus)
    case "stt": return rgSTTSettingsController(context: context, focusSetting: focus)
    case "linkPreview": return rgLinkPreviewSettingsController(context: context, focusSetting: focus)
    case "antiFeatures": return rgAntiFeaturesController(context: context, focusSetting: focus)
    case "ghostMode": return rgGhostModeController(context: context, focusSetting: focus)
    case "fonts": return rgFontSettingsController(context: context, focusSetting: focus)
    case "backup": return rgSettingsBackupController(context: context, focusSetting: focus)
    case "diagnostics":
        if focus == "datacenters" { return rgDatacenterDiagnosticsController(context: context, focusSetting: "start") }
        return rgDiagnosticsController(context: context, focusSetting: focus)
    case "datacenters": return rgDatacenterDiagnosticsController(context: context, focusSetting: focus)
    case "bookmarks": return rgBookmarksController(context: context, focusSetting: focus)
    case "chatPreferences": return rgChatPreferencesController(context: context, focusSetting: focus)
    case "messageFilter": return rgMessageFilterController(context: context, presentationData: presentationData)
    case "hiddenUsers": return rgHiddenUsersController(context: context)
    case "revokedMarker": return rgRevokedMarkerController(context: context, focusSetting: focus)
    case "antiRevokeChats": return rgAntiRevokeChatsController(context: context)
    case "revokedMessages": return rgRevokedMessagesController(context: context)
    case "appIcons": return themeSettingsController(context: context, focusOnItemTag: .icon)
    case "appBadges": return rgAppBadgeSettingsController(context: context, presentationData: presentationData)
    case "contextMenu": return rgContextMenuOrderController(context: context)
    default: return nil
    }
}

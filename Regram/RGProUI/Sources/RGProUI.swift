import RGSwiftUI
// MARK: Regram — local enhancement settings, organized into focused pages.
import RGSettingsUI
import Foundation
import UIKit
import UniformTypeIdentifiers
import RGItemListUI
import UndoUI
import AccountContext
import Display
import TelegramCore
import Postbox
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils
import TelegramUIPreferences
import SettingsUI

// Optional
import RGSimpleSettings
import RGLogging
import RGStrings

public enum RGProSettingsPage: String {
    case home, messages, input, privacy, translation, media, appearance, notifications, network, tools
    var titleKey: String { "Settings.ProCategory." + self.rawValue }
}

private enum RGProControllerSection: Int32, RGItemListSection {
    // Keep section identities distinct when combined with RGSettingsUI controls.
    case search = 100
    case base
    case antiFeatures
    case appearance
    case notifications
    case footer
    case translation
    case media
    case input
    case network
    case pangu
}

private enum RGProDisclosureLink: String {
    case messagesPage
    case inputPage
    case networkPage
    case privacyPage
    case translationPage
    case mediaPage
    case appearancePage
    case notificationsPage
    case toolsPage
    case translationSettings
    case transcriptionSettings
    case linkPreviewSettings
    case messageActionsSettings
    case chatListSettings
    case folderSettings
    case profileSettings
    case storiesSettings
    case appearanceSettings
    case mediaSettings
    case photoSettings
    case stickerSettings
    case recordingSettings
    case appUpdate
    case appSettings
    case inputSettings
    case transferSettings
    case networkPolicy
    case summarySettings
    case privacySettings
    case bookmarks

    case antiFeatures
    case ghostMode
    case messageFilter
    case hiddenUsers
    case antiRevokeChats
    case appIcons
    case appBages
    case fonts
    case backup
    case chatPreferences
    case revokedMessages
    case diagnostics
}

private enum RGProToggles: String {
    case inputToolbar
    // MARK: Regram
    case mentionAsUserIdLink
    case localPremium
    case disableLinkPreview
    case panguSpacing
    case enablePanguOnReceiving
    case enablePanguOnEditing
    case filterNotifications
    case hideTabBarPermissionWarnings
}

private enum RGProOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
    case defaultOutgoingFormatting
}

private enum RGProAction: String {

    case eraseAllData
}

private typealias RGProControllerEntry = RGItemListUIEntry<RGProControllerSection, RGProToggles, AnyHashable, RGProOneFromManySetting, RGProDisclosureLink, RGProAction>

private func RGProControllerEntries(presentationData: PresentationData, page: RGProSettingsPage, searchQuery: String) -> [RGProControllerEntry] {
    var entries: [RGProControllerEntry] = []
    let lang = presentationData.strings.rgLanguageCode
    
    let id = RGItemListCounter()
    if page == .home {
        entries.append(.searchInput(id: id.count, section: .search, title: NSAttributedString(string: ""), text: searchQuery, placeholder: presentationData.strings.Common_Search))
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            // Match the small, grouped categories on Telegram's settings home.
            let groups: [(RGProControllerSection, [(RGProDisclosureLink, RGProSettingsPage)])] = [
                (.base, [(.messagesPage, .messages), (.inputPage, .input), (.translationPage, .translation)]),
                (.appearance, [(.privacyPage, .privacy), (.mediaPage, .media), (.appearancePage, .appearance), (.notificationsPage, .notifications)]),
                (.network, [(.networkPage, .network), (.toolsPage, .tools)])
            ]
            for (section, destinations) in groups {
                for (link, destination) in destinations {
                    entries.append(.disclosure(id: id.count, section: section, link: link, text: destination.titleKey.i18n(lang)))
                }
            }
        } else {
            let matches = Set(RGSettingsCatalog.results(query: query, language: lang).map(\.id))
            for (index, entry) in RGSettingsCatalog.entries.enumerated() where matches.contains(entry.id) {
                entries.append(.settingsResult(id: 10_000 + index, section: .base, entry: entry))
            }
            // This row must never reuse a category's identity: native text/disclosure nodes
            // have different update contracts and cannot replace each other in place.
            if entries.count == 1 { entries.append(.notice(id: 9_999, section: .base, text: "Settings.Search.NoResults".i18n(lang))) }
        }
        return entries
    }
    
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .messageFilter, text: "MessageFilter.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .hiddenUsers, text: "HiddenUsers.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .input, settingName: .inputToolbar, value: RGSimpleSettings.shared.inputToolbar, text: "InputToolbar.Title".i18n(lang), enabled: true))
    // MARK: Regram
    entries.append(.toggle(id: id.count, section: .input, settingName: .mentionAsUserIdLink, value: RGSimpleSettings.shared.mentionAsUserIdLink, text: "Mention.UserIdLink".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .input, text: "Mention.UserIdLink.Notice".i18n(lang)))
    // MARK: Regram — local Premium switch.
    entries.append(.toggle(id: id.count, section: .footer, settingName: .localPremium, value: RGSimpleSettings.shared.localPremium, text: "LocalPremium.Title".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .footer, text: "LocalPremium.Notice".i18n(lang)))
    // MARK: Regram — link previews off.
    entries.append(.toggle(id: id.count, section: .media, settingName: .disableLinkPreview, value: RGSimpleSettings.shared.disableLinkPreview, text: "LinkPreview.Disable".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .media, text: "LinkPreview.Disable.Notice".i18n(lang)))
    entries.append(.oneFromManySelector(id: id.count, section: .input, settingName: .defaultOutgoingFormatting, text: "OutgoingFormatting.Title".i18n(lang), value: "OutgoingFormatting.\(RGSimpleSettings.shared.defaultOutgoingFormat.rawValue)".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .input, text: "OutgoingFormatting.Notice".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .input, link: .chatPreferences, text: "ChatPreferences.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .antiFeatures, text: "AntiFeatures.Header".i18n(lang)))
    // MARK: Regram — chats anti-revoke is on for individually (toggled from their profile).
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .antiRevokeChats, text: "AntiRevoke.Chats.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .revokedMessages, text: "Revoked.Title".i18n(lang)))
    // MARK: Regram — ghost mode.
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .ghostMode, text: "Ghost.Header".i18n(lang)))

    

    entries.append(.header(id: id.count, section: .notifications, text: presentationData.strings.Notifications_Title.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .notifications, settingName: .hideTabBarPermissionWarnings, value: RGSimpleSettings.shared.hideTabBarPermissionWarnings, text: "features.HideTabBarPermissionWarnings".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .notifications, text: "features.HideTabBarPermissionWarnings.Notice".i18n(lang)))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .pinnedMessageNotifications, text: "Notifications.PinnedMessages.Title".i18n(lang), value: "Notifications.PinnedMessages.value.\(RGSimpleSettings.shared.pinnedMessageNotifications)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .mentionsAndRepliesNotifications, text: "Notifications.MentionsAndReplies.Title".i18n(lang), value: "Notifications.MentionsAndReplies.value.\(RGSimpleSettings.shared.mentionsAndRepliesNotifications)".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .notifications, settingName: .filterNotifications, value: RGSimpleSettings.shared.filterNotifications, text: "Notifications.ContentFilter".i18n(lang), enabled: RGSimpleSettings.shared.canSharePreferencesWithExtensions))
    entries.append(.notice(id: id.count, section: .notifications, text: (RGSimpleSettings.shared.canSharePreferencesWithExtensions ? "Notifications.ContentFilter.Notice" : "Notifications.ContentFilter.Unavailable").i18n(lang)))
    entries.append(.header(id: id.count, section: .appearance, text: "Settings.Section.Personalization".i18n(lang), badge: nil))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fonts, text: "Fonts.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appIcons, text: presentationData.strings.Appearance_AppIcon))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appBages, text: "AppBadge.Title".i18n(lang)))
    entries.append(.notice(id: id.count, section: .appearance, text: "AppBadge.Notice".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .footer, link: .backup, text: "Backup.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .network, link: .diagnostics, text: "Diagnostics.Title".i18n(lang)))

    entries.append(.action(id: id.count, section: .footer, actionType: .eraseAllData, text: "EraseData.Title".i18n(lang), kind: .destructive))
    entries.append(.notice(id: id.count, section: .footer, text: "EraseData.Notice".i18n(lang)))

    #if DEBUG
    #endif
    
    entries.append(.disclosure(id: id.count, section: .base, link: .summarySettings, text: "Summary.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .messageActionsSettings, text: RGSettingsPage.messageActions.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .chatListSettings, text: RGSettingsPage.chatList.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .folderSettings, text: RGSettingsPage.folders.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .translation, link: .translationSettings, text: RGSettingsPage.translation.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .translation, link: .transcriptionSettings, text: RGSettingsPage.transcription.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .media, link: .linkPreviewSettings, text: "LinkPreview.Repair".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .media, link: .photoSettings, text: RGSettingsPage.photos.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .media, link: .stickerSettings, text: RGSettingsPage.stickers.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .media, link: .recordingSettings, text: RGSettingsPage.recording.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .media, link: .mediaSettings, text: RGSettingsPage.media.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appearanceSettings, text: RGSettingsPage.appearance.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .profileSettings, text: RGSettingsPage.profiles.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .storiesSettings, text: RGSettingsPage.stories.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .privacySettings, text: RGSettingsPage.privacy.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .footer, link: .appUpdate, text: "AppUpdate.Title".i18n(lang)))

    entries.append(.disclosure(id: id.count, section: .input, link: .inputSettings, text: RGSettingsPage.input.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .network, link: .networkPolicy, text: "NetworkPolicy.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .network, link: .transferSettings, text: RGSettingsPage.transfer.titleKey.i18n(lang)))

    // MARK: Regram — the receiving, sending and editing choices share one visible group.
    entries.append(.header(id: id.count, section: .pangu, text: "Pangu.Title".i18n(lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .pangu, settingName: .enablePanguOnReceiving, value: RGSimpleSettings.shared.enablePanguOnReceiving, text: "features.PanguOnReceiving".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .pangu, settingName: .panguSpacing, value: RGSimpleSettings.shared.enablePanguOnSending, text: "features.PanguOnSending".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .pangu, settingName: .enablePanguOnEditing, value: RGSimpleSettings.shared.enablePanguOnEditing, text: "features.PanguOnEditing".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .pangu, text: "features.PanguInfo".i18n(lang)))

    let section: RGProControllerSection
    switch page {
    case .home, .messages: section = .base
    case .input: section = .input
    case .network: section = .network
    case .privacy: section = .antiFeatures
    case .translation: section = .translation
    case .media: section = .media
    case .appearance: section = .appearance
    case .notifications: section = .notifications
    case .tools: section = .footer
    }
    if page == .input {
        return [.header(id: -1, section: .input, text: "Settings.Section.Composer".i18n(lang), badge: nil)] + entries.filter { $0.section == section.rawValue } + entries.filter { $0.section == RGProControllerSection.pangu.rawValue }
    }
    let headerKey: String?
    switch page {
    case .messages: headerKey = "Summary.Title"
    case .privacy: headerKey = "Settings.Section.PrivacyControls"
    case .media: headerKey = "Settings.Section.Links"
    case .network: headerKey = "Settings.Section.Connection"
    case .tools: headerKey = "Settings.ProCategory.tools"
    default: headerKey = nil
    }
    // Header identity must also stay distinct from the first privacy control (id 0).
    let header: [RGProControllerEntry] = headerKey.map { [.header(id: -1, section: section, text: $0.i18n(lang), badge: nil)] } ?? []
    return header + entries.filter { $0.section == section.rawValue }

}

public func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}

public func rgProController(context: AccountContext, initialSearchQuery: String? = nil, page: RGProSettingsPage = .home, focusSetting: String? = nil, initialSettingsPage: RGSettingsPage? = nil) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var askForRestart: (() -> Void)?

    var cancelSearchSelection: (() -> Void)?
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    let searchPromise = ValuePromise(initialSearchQuery ?? "", ignoreRepeated: true)
    var searchGeneration = 0

    let arguments = RGItemListArguments<RGProToggles, AnyHashable, RGProOneFromManySetting, RGProDisclosureLink, RGProAction>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .inputToolbar:
                RGSimpleSettings.shared.inputToolbar = value
            case .mentionAsUserIdLink:
                RGSimpleSettings.shared.mentionAsUserIdLink = value
            case .localPremium:
                RGSimpleSettings.shared.localPremium = value
                // Screens that already read the old value keep it until they are rebuilt, so offer
                // a restart the way the main Regram settings do.
                askForRestart?()
            case .disableLinkPreview:
                // Read live on every preview query, so no restart is needed.
                RGSimpleSettings.shared.disableLinkPreview = value
            case .enablePanguOnReceiving:
                RGSimpleSettings.shared.enablePanguOnReceiving = value
            case .enablePanguOnEditing:
                RGSimpleSettings.shared.enablePanguOnEditing = value
            case .panguSpacing:
                // Read on each send, so no restart is needed.
                RGSimpleSettings.shared.enablePanguOnSending = value
            case .filterNotifications:
                RGSimpleSettings.shared.filterNotifications = value
                RGSimpleSettings.shared.synchronizeShared()
            case .hideTabBarPermissionWarnings:
                RGSimpleSettings.shared.hideTabBarPermissionWarnings = value
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.rgLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .defaultOutgoingFormatting:
                for format in RGSimpleSettings.DefaultOutgoingFormat.allCases {
                    items.append(ActionSheetButtonItem(title: "OutgoingFormatting.\(format.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        RGSimpleSettings.shared.defaultOutgoingFormatting = format.rawValue
                        simplePromise.set(true)
                    }))
                }
            case .pinnedMessageNotifications:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.pinnedMessageNotifications = value
                    RGSimpleSettings.shared.synchronizeShared()
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.PinnedMessageNotificationsSettings.allCases {
                    items.append(ActionSheetButtonItem(title: "Notifications.PinnedMessages.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .mentionsAndRepliesNotifications:
                let setAction: (String) -> Void = { value in
                    RGSimpleSettings.shared.mentionsAndRepliesNotifications = value
                    RGSimpleSettings.shared.synchronizeShared()
                    simplePromise.set(true)
                }

                for value in RGSimpleSettings.MentionsAndRepliesNotificationsSettings.allCases {
                    items.append(ActionSheetButtonItem(title: "Notifications.MentionsAndReplies.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
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
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch (link) {
            case .inputPage: pushControllerImpl?(rgProController(context: context, page: .input))
            case .networkPage: pushControllerImpl?(rgProController(context: context, page: .network))
            case .bookmarks: pushControllerImpl?(rgBookmarksController(context: context))
            case .inputSettings: pushControllerImpl?(rgSettingsController(context: context, page: .input))
            case .summarySettings: pushControllerImpl?(rgLLMSummarySettingsController(context: context))
            case .networkPolicy: pushControllerImpl?(rgNetworkPolicyController(context: context))
            case .transferSettings: pushControllerImpl?(rgSettingsController(context: context, page: .transfer))
            case .privacySettings: pushControllerImpl?(rgSettingsController(context: context, page: .privacy))
            case .messagesPage: pushControllerImpl?(rgProController(context: context, page: .messages))
            case .privacyPage: pushControllerImpl?(rgProController(context: context, page: .privacy))
            case .translationPage: pushControllerImpl?(rgProController(context: context, page: .translation))
            case .mediaPage: pushControllerImpl?(rgProController(context: context, page: .media))
            case .appearancePage: pushControllerImpl?(rgProController(context: context, page: .appearance))
            case .notificationsPage: pushControllerImpl?(rgProController(context: context, page: .notifications))
            case .toolsPage: pushControllerImpl?(rgProController(context: context, page: .tools))
            case .translationSettings: pushControllerImpl?(rgSettingsController(context: context, page: .translation))
            case .transcriptionSettings: pushControllerImpl?(rgSettingsController(context: context, page: .transcription))
            case .messageActionsSettings: pushControllerImpl?(rgSettingsController(context: context, page: .messageActions))
            case .chatListSettings: pushControllerImpl?(rgSettingsController(context: context, page: .chatList))
            case .folderSettings: pushControllerImpl?(rgSettingsController(context: context, page: .folders))
            case .profileSettings: pushControllerImpl?(rgSettingsController(context: context, page: .profiles))
            case .storiesSettings: pushControllerImpl?(rgSettingsController(context: context, page: .stories))
            case .appearanceSettings: pushControllerImpl?(rgSettingsController(context: context, page: .appearance))
            case .mediaSettings: pushControllerImpl?(rgSettingsController(context: context, page: .media))
            case .photoSettings: pushControllerImpl?(rgSettingsController(context: context, page: .photos))
            case .stickerSettings: pushControllerImpl?(rgSettingsController(context: context, page: .stickers))
            case .recordingSettings: pushControllerImpl?(rgSettingsController(context: context, page: .recording))
            case .linkPreviewSettings: pushControllerImpl?(rgLinkPreviewSettingsController(context: context))
            case .appUpdate: pushControllerImpl?(rgAppUpdateController(context: context))
            case .appSettings: pushControllerImpl?(rgSettingsController(context: context, page: .app))

            case .antiFeatures:
                pushControllerImpl?(rgAntiFeaturesController(context: context))
            case .ghostMode:
                pushControllerImpl?(rgGhostModeController(context: context))
            case .messageFilter:
                pushControllerImpl?(rgMessageFilterController(context: context, presentationData: presentationData))
            case .hiddenUsers:
                pushControllerImpl?(rgHiddenUsersController(context: context))
            case .antiRevokeChats:
                pushControllerImpl?(rgAntiRevokeChatsController(context: context))
            case .fonts:
                pushControllerImpl?(rgFontSettingsController(context: context))
            case .backup: pushControllerImpl?(rgSettingsBackupController(context: context))
            case .chatPreferences: pushControllerImpl?(rgChatPreferencesController(context: context))
            case .revokedMessages: pushControllerImpl?(rgRevokedMessagesController(context: context))
            case .diagnostics: pushControllerImpl?(rgDiagnosticsController(context: context))
            case .appIcons:
                pushControllerImpl?(themeSettingsController(context: context, focusOnItemTag: .icon))
            case .appBages:
                if #available(iOS 14.0, *) {
                    pushControllerImpl?(rgAppBadgeSettingsController(context: context, presentationData: presentationData))
                } else {
                    presentControllerImpl?(context.sharedContext.makeRGUpdateIOSController(), nil)
                }
        }
    }, action: { action in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch action {
            case .eraseAllData:
                let lang = presentationData.strings.rgLanguageCode
                let actionSheet = ActionSheetController(presentationData: presentationData)
                actionSheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "EraseData.Confirm".i18n(lang)),
                        ActionSheetButtonItem(title: "EraseData.Action".i18n(lang), color: .destructive, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            // Arms the launch-time wipe and closes the app: the deletion has to
                            // happen before anything opens the database, which is the one place
                            // rgFullWipeIfNeeded runs.
                            UserDefaults.standard.set(true, forKey: "rg_full_wipe")
                            UserDefaults.standard.set(lang, forKey: "Regram.Reset.Language")
                            UserDefaults.standard.synchronize()
                            exit(0)
                        })
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }
    }, searchInput: { value in
        cancelSearchSelection?()
        // Finish UIKit's input event, then publish only the newest edit (including clearing).
        searchGeneration += 1
        let generation = searchGeneration
        Queue.mainQueue().async {
            guard generation == searchGeneration else { return }
            searchPromise.set(value)
        }
    }, settingsPage: "pro." + page.rawValue, openSettingsResult: { destination in
        if let controller = rgControllerForSettingsLink(context: context, destination: destination) { pushControllerImpl?(controller) }
    }, disclosureIcon: { link in
        // Category artwork stays native; specialised editors use distinct, centered symbols.
        switch link {
        case .messagesPage: return PresentationResourcesSettings.messages
        case .inputPage: return PresentationResourcesSettings.upload
        case .translationPage: return PresentationResourcesSettings.language
        case .privacyPage: return PresentationResourcesSettings.security
        case .mediaPage: return PresentationResourcesSettings.photos
        case .appearancePage: return PresentationResourcesSettings.appearance
        case .notificationsPage: return PresentationResourcesSettings.notifications
        case .networkPage: return PresentationResourcesSettings.proxy
        case .toolsPage: return PresentationResourcesSettings.settings
        case .fonts: return RGSettingsIcons.fonts
        case .appIcons: return RGSettingsIcons.appIcon
        case .appBages: return RGSettingsIcons.screenshotBadge
        case .transcriptionSettings: return RGSettingsIcons.transcription
        case .summarySettings: return RGSettingsIcons.summary
        // The privacy group already has a clear heading. Keep all its titles aligned without icons.
        case .messageFilter, .hiddenUsers, .antiFeatures, .antiRevokeChats, .ghostMode, .revokedMessages: return nil
        case .linkPreviewSettings: return nil
        case .networkPolicy: return RGSettingsIcons.network
        case .diagnostics: return RGSettingsIcons.diagnostics
        case .backup: return RGSettingsIcons.backup
        case .appUpdate: return RGSettingsIcons.update
        default: return nil
        }
    }, disclosureSubtitle: { link in
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.rgLanguageCode
        let category: RGProSettingsPage?
        switch link {
        case .messagesPage: category = .messages
        case .inputPage: category = .input
        case .translationPage: category = .translation
        case .privacyPage: category = .privacy
        case .mediaPage: category = .media
        case .appearancePage: category = .appearance
        case .notificationsPage: category = .notifications
        case .networkPage: category = .network
        case .toolsPage: category = .tools
        default: category = nil
        }
        if let category { return (category.titleKey + ".Description").i18n(lang) }
        switch link {
        case .fonts, .appBages, .transcriptionSettings, .summarySettings, .linkPreviewSettings, .messageFilter, .networkPolicy, .diagnostics:
            return ("Settings.Editor." + link.rawValue + ".Description").i18n(lang)
        default: return nil
        }
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get(), searchPromise.get())
    |> map { presentationData, _, query ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = RGProControllerEntries(presentationData: presentationData, page: page, searchQuery: query)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(page == .home ? "Settings.Pro.Title".i18n(presentationData.strings.rgLanguageCode) : page.titleKey.i18n(presentationData.strings.rgLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: rgSettingsScrollTarget(entries, item: focusSetting), animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    
    let controller: ViewController
    if let layout = RGProCategoryLayout(page: page) {
        controller = rgSettingsController(context: context, page: layout.pages[0], focusSetting: focusSetting, additionalPages: Array(layout.pages.dropFirst()), usesTabs: layout.usesTabs, initialPage: initialSettingsPage, titleKey: page.titleKey, additionalUpdates: simplePromise.get(), additionalContent: { presentationData, activePage in
            let rows = RGProControllerEntries(presentationData: presentationData, page: page, searchQuery: "").filter { entry in
                if layout.usesTabs && activePage != layout.pages[0] { return false }
                guard case let .disclosure(_, _, link, _) = entry else { return true }
                return !RGProCategoryLayout.inlinedLinks.contains(link.rawValue)
            }
            let bound = rows.map { RGSettingsBoundEntry($0, arguments: arguments, scope: "pro." + page.rawValue, order: 0) }
            if page == .translation {
                let header = RGProControllerEntry.header(id: 50_001, section: .translation, text: "Settings.Section.Speech".i18n(presentationData.strings.rgLanguageCode), badge: nil)
                return RGSettingsSupplement(trailing: [RGSettingsBoundEntry(header, arguments: arguments, scope: "pro.translation", order: 0)] + bound)
            }
            if page == .input {
                return RGSettingsSupplement(leading: zip(rows, bound).filter { $0.0.section != RGProControllerSection.pangu.rawValue }.map { $0.1 }, trailing: zip(rows, bound).filter { $0.0.section == RGProControllerSection.pangu.rawValue }.map { $0.1 })
            }
            return RGSettingsSupplement(leading: bound)
        })
    } else {
        let listController = RGSettingsListController(context: context, state: signal)
        listController.focusSetting = focusSetting
        controller = listController
    }
    cancelSearchSelection = { [weak controller] in
        ((controller?.displayNode as? ItemListControllerNode)?.listNode as? ListViewImpl)?.cancelSelection()
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    askForRestart = { [weak context] in
        guard let context = context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.rgLanguageCode
        presentControllerImpl?(
            UndoOverlayController(
                presentationData: presentationData,
                content: .info(
                    title: nil,
                    text: "Common.RestartRequired".i18n(lang),
                    timeout: nil,
                    customUndoText: "Common.RestartNow".i18n(lang)
                ),
                elevatedLayout: false,
                action: { action in if action == .undo { exit(0) }; return true }
            ),
            nil
        )
    }
    // Workaround
    let _ = pushControllerImpl


    return controller
}

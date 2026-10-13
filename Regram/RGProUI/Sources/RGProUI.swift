// MARK: Regram — local enhancement settings, organized into focused pages.
import RGSettingsUI
import Foundation
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
    case home, messages, privacy, translation, media, appearance, notifications, tools
    var titleKey: String { "Settings.ProCategory." + self.rawValue }
}

private enum RGProControllerSection: Int32, RGItemListSection {
    case base
    case antiFeatures
    case appearance
    case notifications
    case footer
    case translation
    case media
}

private enum RGProDisclosureLink: String {
    case messagesPage
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
    case filterNotifications
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

private func RGProControllerEntries(presentationData: PresentationData, page: RGProSettingsPage) -> [RGProControllerEntry] {
    var entries: [RGProControllerEntry] = []
    let lang = presentationData.strings.baseLanguageCode
    
    let id = RGItemListCounter()
    if page == .home {
        for (link, destination) in [(RGProDisclosureLink.messagesPage, RGProSettingsPage.messages), (.translationPage, .translation), (.privacyPage, .privacy), (.mediaPage, .media), (.appearancePage, .appearance), (.notificationsPage, .notifications), (.toolsPage, .tools)] {
            entries.append(.disclosure(id: id.count, section: .base, link: link, text: destination.titleKey.i18n(lang)))
        }
        return entries
    }
    
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .messageFilter, text: "MessageFilter.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .hiddenUsers, text: "HiddenUsers.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .base, settingName: .inputToolbar, value: RGSimpleSettings.shared.inputToolbar, text: "InputToolbar.Title".i18n(lang), enabled: true))
    // MARK: Regram
    entries.append(.toggle(id: id.count, section: .base, settingName: .mentionAsUserIdLink, value: RGSimpleSettings.shared.mentionAsUserIdLink, text: "Mention.UserIdLink".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "Mention.UserIdLink.Notice".i18n(lang)))
    // MARK: Regram — local Premium switch.
    entries.append(.toggle(id: id.count, section: .antiFeatures, settingName: .localPremium, value: RGSimpleSettings.shared.localPremium, text: "LocalPremium.Title".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .antiFeatures, text: "LocalPremium.Notice".i18n(lang)))
    // MARK: Regram — link previews off.
    entries.append(.toggle(id: id.count, section: .media, settingName: .disableLinkPreview, value: RGSimpleSettings.shared.disableLinkPreview, text: "LinkPreview.Disable".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .media, text: "LinkPreview.Disable.Notice".i18n(lang)))
    // MARK: Regram — pangu spacing.
    entries.append(.toggle(id: id.count, section: .base, settingName: .panguSpacing, value: RGSimpleSettings.shared.panguSpacing, text: "Pangu.Title".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "Pangu.Notice".i18n(lang)))
    entries.append(.oneFromManySelector(id: id.count, section: .base, settingName: .defaultOutgoingFormatting, text: "OutgoingFormatting.Title".i18n(lang), value: "OutgoingFormatting.\(RGSimpleSettings.shared.defaultOutgoingFormat.rawValue)".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "OutgoingFormatting.Notice".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .chatPreferences, text: "ChatPreferences.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .antiFeatures, text: "AntiFeatures.Header".i18n(lang)))
    // MARK: Regram — chats anti-revoke is on for individually (toggled from their profile).
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .antiRevokeChats, text: "AntiRevoke.Chats.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .revokedMessages, text: "Revoked.Title".i18n(lang)))
    // MARK: Regram — ghost mode.
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .ghostMode, text: "Ghost.Header".i18n(lang)))

    

    entries.append(.header(id: id.count, section: .notifications, text: presentationData.strings.Notifications_Title.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .pinnedMessageNotifications, text: "Notifications.PinnedMessages.Title".i18n(lang), value: "Notifications.PinnedMessages.value.\(RGSimpleSettings.shared.pinnedMessageNotifications)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .mentionsAndRepliesNotifications, text: "Notifications.MentionsAndReplies.Title".i18n(lang), value: "Notifications.MentionsAndReplies.value.\(RGSimpleSettings.shared.mentionsAndRepliesNotifications)".i18n(lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .notifications, settingName: .filterNotifications, value: RGSimpleSettings.shared.filterNotifications, text: "Notifications.ContentFilter".i18n(lang), enabled: RGSimpleSettings.shared.canSharePreferencesWithExtensions))
    entries.append(.notice(id: id.count, section: .notifications, text: (RGSimpleSettings.shared.canSharePreferencesWithExtensions ? "Notifications.ContentFilter.Notice" : "Notifications.ContentFilter.Unavailable").i18n(lang)))
    entries.append(.header(id: id.count, section: .appearance, text: presentationData.strings.Appearance_Title.uppercased(), badge: nil))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fonts, text: "Fonts.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appIcons, text: presentationData.strings.Appearance_AppIcon))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appBages, text: "AppBadge.Title".i18n(lang)))
    entries.append(.notice(id: id.count, section: .appearance, text: "AppBadge.Notice".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .footer, link: .backup, text: "Backup.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .footer, link: .diagnostics, text: "Diagnostics.Title".i18n(lang)))

    entries.append(.action(id: id.count, section: .footer, actionType: .eraseAllData, text: "EraseData.Title".i18n(lang), kind: .destructive))
    entries.append(.notice(id: id.count, section: .footer, text: "EraseData.Notice".i18n(lang)))

    #if DEBUG
    #endif
    
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
    entries.append(.disclosure(id: id.count, section: .footer, link: .appSettings, text: RGSettingsPage.app.titleKey.i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .footer, link: .appUpdate, text: "Updates.Title".i18n(lang)))

    let section: RGProControllerSection
    switch page {
    case .home, .messages: section = .base
    case .privacy: section = .antiFeatures
    case .translation: section = .translation
    case .media: section = .media
    case .appearance: section = .appearance
    case .notifications: section = .notifications
    case .tools: section = .footer
    }
    return entries.filter { $0.section == section.rawValue }

}

public func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}

public func rgProController(context: AccountContext, initialSearchQuery: String? = nil, page: RGProSettingsPage = .home) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var askForRestart: (() -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)

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
            case .panguSpacing:
                // Read on each send, so no restart is needed.
                RGSimpleSettings.shared.panguSpacing = value
            case .filterNotifications:
                RGSimpleSettings.shared.filterNotifications = value
                RGSimpleSettings.shared.synchronizeShared()
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
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
                let lang = presentationData.strings.baseLanguageCode
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
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = RGProControllerEntries(presentationData: presentationData, page: page)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(page == .home ? "Regram Pro" : page.titleKey.i18n(presentationData.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
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
    askForRestart = { [weak context] in
        guard let context = context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
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

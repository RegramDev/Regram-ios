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

private enum RGProControllerSection: Int32, RGItemListSection {
    case base
    case antiFeatures
    case appearance
    case notifications
    case footer
}

private enum RGProDisclosureLink: String {
    case antiFeatures
    case ghostMode
    case sessionBackupManager
    case messageFilter
    case hiddenUsers
    case appIcons
    case appBages
}

private enum RGProToggles: String {
    case inputToolbar
    // MARK: Regram
    case mentionAsUserIdLink
    case nsfwEnabled
    case localPremium
    case disableLinkPreview
    case panguSpacing
}

private enum RGProOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
}

private enum RGProAction {
    case resetIAP
    case eraseAllData
}

private typealias RGProControllerEntry = RGItemListUIEntry<RGProControllerSection, RGProToggles, AnyHashable, RGProOneFromManySetting, RGProDisclosureLink, RGProAction>

private func RGProControllerEntries(presentationData: PresentationData) -> [RGProControllerEntry] {
    var entries: [RGProControllerEntry] = []
    let lang = presentationData.strings.baseLanguageCode
    
    let id = RGItemListCounter()
    
    entries.append(.disclosure(id: id.count, section: .base, link: .sessionBackupManager, text: "SessionBackup.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .messageFilter, text: "MessageFilter.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .hiddenUsers, text: "HiddenUsers.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .base, settingName: .inputToolbar, value: RGSimpleSettings.shared.inputToolbar, text: "InputToolbar.Title".i18n(lang), enabled: true))
    // MARK: Regram
    entries.append(.toggle(id: id.count, section: .base, settingName: .mentionAsUserIdLink, value: RGSimpleSettings.shared.mentionAsUserIdLink, text: "Mention.UserIdLink".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "Mention.UserIdLink.Notice".i18n(lang)))
    // MARK: Regram — NSFW section switch.
    entries.append(.toggle(id: id.count, section: .base, settingName: .nsfwEnabled, value: RGSimpleSettings.shared.nsfwEnabled, text: "NSFW.Title".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "NSFW.Notice".i18n(lang)))
    // MARK: Regram — local Premium switch.
    entries.append(.toggle(id: id.count, section: .base, settingName: .localPremium, value: RGSimpleSettings.shared.localPremium, text: "LocalPremium.Title".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "LocalPremium.Notice".i18n(lang)))
    // MARK: Regram — link previews off.
    entries.append(.toggle(id: id.count, section: .base, settingName: .disableLinkPreview, value: RGSimpleSettings.shared.disableLinkPreview, text: "LinkPreview.Disable".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "LinkPreview.Disable.Notice".i18n(lang)))
    // MARK: Regram — pangu spacing.
    entries.append(.toggle(id: id.count, section: .base, settingName: .panguSpacing, value: RGSimpleSettings.shared.panguSpacing, text: "Pangu.Title".i18n(lang), enabled: true))
    entries.append(.notice(id: id.count, section: .base, text: "Pangu.Notice".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .antiFeatures, text: "AntiFeatures.Header".i18n(lang)))
    // MARK: Regram — ghost mode.
    entries.append(.disclosure(id: id.count, section: .antiFeatures, link: .ghostMode, text: "Ghost.Header".i18n(lang)))

    

    entries.append(.header(id: id.count, section: .notifications, text: presentationData.strings.Notifications_Title.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .pinnedMessageNotifications, text: "Notifications.PinnedMessages.Title".i18n(lang), value: "Notifications.PinnedMessages.value.\(RGSimpleSettings.shared.pinnedMessageNotifications)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .mentionsAndRepliesNotifications, text: "Notifications.MentionsAndReplies.Title".i18n(lang), value: "Notifications.MentionsAndReplies.value.\(RGSimpleSettings.shared.mentionsAndRepliesNotifications)".i18n(lang), enabled: true))
    entries.append(.header(id: id.count, section: .appearance, text: presentationData.strings.Appearance_Title.uppercased(), badge: nil))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appIcons, text: presentationData.strings.Appearance_AppIcon))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appBages, text: "AppBadge.Title".i18n(lang)))
    entries.append(.notice(id: id.count, section: .appearance, text: "AppBadge.Notice".i18n(lang)))

    entries.append(.action(id: id.count, section: .footer, actionType: .eraseAllData, text: "EraseData.Title".i18n(lang), kind: .destructive))
    entries.append(.notice(id: id.count, section: .footer, text: "EraseData.Notice".i18n(lang)))

    #if DEBUG
    entries.append(.action(id: id.count, section: .footer, actionType: .resetIAP, text: "Reset Pro", kind: .destructive))
    #endif
    
    return entries
}

public func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}

public func rgProController(context: AccountContext) -> ViewController {
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
            case .nsfwEnabled:
                RGSimpleSettings.shared.nsfwEnabled = value
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
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
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
            case .sessionBackupManager:
                pushControllerImpl?(rgSessionBackupManagerController(context: context, presentationData: presentationData))
            case .antiFeatures:
                pushControllerImpl?(rgAntiFeaturesController(context: context))
            case .ghostMode:
                pushControllerImpl?(rgGhostModeController(context: context))
            case .messageFilter:
                pushControllerImpl?(rgMessageFilterController(context: context, presentationData: presentationData))
            case .hiddenUsers:
                pushControllerImpl?(rgHiddenUsersController(context: context))
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
                            UserDefaults.standard.set(true, forKey: "sg_full_wipe")
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
            case .resetIAP:
                let updateSettingsSignal = updateRGStatusInteractively(accountManager: context.sharedContext.accountManager, { status in
                    var status = status
                    status.status = RGStatus.default.status
                    RGSimpleSettings.shared.primaryUserId = ""
                    return status
                })
                let _ = (updateSettingsSignal |> deliverOnMainQueue).start(next: {
                    presentControllerImpl?(UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: "Status reset completed. You can now restore purchases.", timeout: nil, customUndoText: nil),
                        elevatedLayout: false,
                        action: { _ in return false }
                    ),
                    nil)
                })
        }
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = RGProControllerEntries(presentationData: presentationData)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Regram Pro"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
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


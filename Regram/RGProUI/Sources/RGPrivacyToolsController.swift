import Foundation
import AccountContext
import Display
import ItemListUI
import RGItemListUI
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramPresentationData

// MARK: Regram
// Sub-page reached from the Regram Pro screen. The anti-deletion toggles are a long enough list
// that inlining them buries the rest of the Pro settings, so they get their own screen behind a
// disclosure row.

private enum RGPrivacyToolsSection: Int32, RGItemListSection {
    case main
}

/// One switch on a privacy sub-page: the `RGSimpleSettings` property it drives and its i18n key.
private struct RGPrivacyToggle {
    let setting: RGPrivacyToolsToggle
    let localizationKey: String
    let get: () -> Bool
    let set: (Bool) -> Void
}

private enum RGPrivacyToolsToggle: String {
    case antiRevoke
    case antiAutoDelete
    case antiSelfDestruct
    case antiScreenshotNotification
    case allowSavingProtectedContent
    case allowDownloadingStories
    case disableAllAds
    // MARK: Regram — ghost mode
    case ghostDontReadMessages
    case ghostDontReadStories
    case ghostDontSendOnline
    case ghostDontSendTyping
}

private typealias RGPrivacyToolsEntry = RGItemListUIEntry<RGPrivacyToolsSection, RGPrivacyToolsToggle, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private func antiFeatureToggles() -> [RGPrivacyToggle] {
    let settings = RGSimpleSettings.shared
    return [
        RGPrivacyToggle(setting: .antiRevoke, localizationKey: "AntiFeatures.Revoke", get: { settings.antiRevoke }, set: { settings.antiRevoke = $0 }),
        RGPrivacyToggle(setting: .antiAutoDelete, localizationKey: "AntiFeatures.AutoDelete", get: { settings.antiAutoDelete }, set: { settings.antiAutoDelete = $0 }),
        RGPrivacyToggle(setting: .antiSelfDestruct, localizationKey: "AntiFeatures.SelfDestruct", get: { settings.antiSelfDestruct }, set: { settings.antiSelfDestruct = $0 }),
        RGPrivacyToggle(setting: .antiScreenshotNotification, localizationKey: "AntiFeatures.Screenshot", get: { settings.antiScreenshotNotification }, set: { settings.antiScreenshotNotification = $0 }),
        RGPrivacyToggle(setting: .allowSavingProtectedContent, localizationKey: "AntiFeatures.SaveProtected", get: { settings.allowSavingProtectedContent }, set: { settings.allowSavingProtectedContent = $0 }),
        RGPrivacyToggle(setting: .allowDownloadingStories, localizationKey: "AntiFeatures.SaveProtectedStories", get: { settings.allowDownloadingStories }, set: { settings.allowDownloadingStories = $0 }),
        RGPrivacyToggle(setting: .disableAllAds, localizationKey: "AntiFeatures.DisableAds", get: { settings.disableAllAds }, set: { settings.disableAllAds = $0 }),
    ]
}

private func rgPrivacyToolsController(context: AccountContext, title: String, noticeKey: String, toggles: [RGPrivacyToggle]) -> ViewController {
    let simplePromise = ValuePromise(true, ignoreRepeated: false)

    let arguments = RGItemListArguments<RGPrivacyToolsToggle, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, setBoolValue: { toggleName, value in
        if let toggle = toggles.first(where: { $0.setting == toggleName }) {
            toggle.set(value)
        }
        simplePromise.set(true)
    })

    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let id = RGItemListCounter()

        var entries: [RGPrivacyToolsEntry] = []
        for toggle in toggles {
            entries.append(.toggle(id: id.count, section: .main, settingName: toggle.setting, value: toggle.get(), text: toggle.localizationKey.i18n(lang), enabled: true))
        }
        entries.append(.notice(id: id.count, section: .main, text: noticeKey.i18n(lang)))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}


public func rgAntiFeaturesController(context: AccountContext) -> ViewController {
    let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    return rgPrivacyToolsController(context: context, title: "AntiFeatures.Header".i18n(lang), noticeKey: "AntiFeatures.Notice", toggles: antiFeatureToggles())
}

// MARK: Regram — ghost mode.
//
// Each switch suppresses one outgoing signal on the TelegramCore network path (see RGGhostMode).
// Nothing here changes what this device shows: chats still read as read, stories still clear their
// ring. Only the request that would tell the other side is dropped.
private func ghostModeToggles() -> [RGPrivacyToggle] {
    let settings = RGSimpleSettings.shared
    return [
        RGPrivacyToggle(setting: .ghostDontReadMessages, localizationKey: "Ghost.DontReadMessages", get: { settings.ghostDontReadMessages }, set: { settings.ghostDontReadMessages = $0 }),
        RGPrivacyToggle(setting: .ghostDontReadStories, localizationKey: "Ghost.DontReadStories", get: { settings.ghostDontReadStories }, set: { settings.ghostDontReadStories = $0 }),
        RGPrivacyToggle(setting: .ghostDontSendOnline, localizationKey: "Ghost.DontSendOnline", get: { settings.ghostDontSendOnline }, set: { settings.ghostDontSendOnline = $0 }),
        RGPrivacyToggle(setting: .ghostDontSendTyping, localizationKey: "Ghost.DontSendTyping", get: { settings.ghostDontSendTyping }, set: { settings.ghostDontSendTyping = $0 }),
    ]
}

public func rgGhostModeController(context: AccountContext) -> ViewController {
    let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    return rgPrivacyToolsController(context: context, title: "Ghost.Header".i18n(lang), noticeKey: "Ghost.Notice", toggles: ghostModeToggles())
}

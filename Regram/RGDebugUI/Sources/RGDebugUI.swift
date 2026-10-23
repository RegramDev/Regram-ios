import Foundation
import WebKit
import RGAppGroupIdentifier
import RGStrings
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

// Optional
import RGSimpleSettings
import RGLogging
import OverlayStatusController
#if DEBUG
import FLEX
#endif


private enum RGDebugControllerSection: Int32, RGItemListSection {
    case base
}

private enum RGDebugDisclosureLink: String {
    case messageFilter
    case debugIAP
}

private enum RGDebugActions: String {
    case flexing
    case fileManager
    case clearRegDateCache
    case clearOutgoingTranslationLanguageCache
    case clearCache



}

private enum RGDebugToggles: String {
    case forceImmediateShareSheet
    case inputToolbar
}


private enum RGDebugOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
}

private typealias RGDebugControllerEntry = RGItemListUIEntry<RGDebugControllerSection, RGDebugToggles, AnyHashable, RGDebugOneFromManySetting, RGDebugDisclosureLink, RGDebugActions>

private func RGDebugControllerEntries(presentationData: PresentationData) -> [RGDebugControllerEntry] {
    var entries: [RGDebugControllerEntry] = []
    let language = RGLocalizationManager.shared.preferredLocale(primary: presentationData.strings.primaryComponent.languageCode, secondary: presentationData.strings.secondaryComponent?.languageCode)
    
    let id = RGItemListCounter()
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .flexing, text: "FLEX", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .fileManager, text: "FileManager", kind: .generic))
    #endif

    entries.append(.action(id: id.count, section: .base, actionType: .clearRegDateCache, text: "Clear Regdate cache", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .clearOutgoingTranslationLanguageCache, text: "Clear Outgoing Translation cache", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .clearCache, text: "Debug.ClearCache".i18n(language), kind: .generic))
    entries.append(.toggle(id: id.count, section: .base, settingName: .forceImmediateShareSheet, value: RGSimpleSettings.shared.forceSystemSharing, text: "Force System Share Sheet", enabled: true))
    
    #if DEBUG
    #endif

    return entries
}

// MARK: Regram — use the storage engine, never remove shared account directories or keys.
private final class RGDebugCacheCleanup {
    private let disposable = MetaDisposable()
    private var spinner: ViewController?
    private(set) var isRunning = false

    deinit {
        self.disposable.dispose()
        self.spinner?.dismiss()
    }

    func start(context: AccountContext, present: @escaping (ViewController, ViewControllerPresentationArguments?) -> Void) {
        guard !self.isRunning else { return }
        self.isRunning = true
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let spinner = OverlayStatusController(theme: data.theme, type: .loading(cancelled: nil))
        self.spinner = spinner
        present(spinner, nil)
        self.disposable.set((context.engine.resources.clearStorage(peerId: nil, categories: [.photos, .videos, .files, .music, .stickers, .avatars, .misc, .stories], includeMessages: [], excludeMessages: [])
        |> deliverOnMainQueue).start(completed: { [weak self] in
            URLCache.shared.removeAllCachedResponses()
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) { [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.spinner?.dismiss()
                self.spinner = nil
                let current = context.sharedContext.currentPresentationData.with { $0 }
                let language = RGLocalizationManager.shared.preferredLocale(primary: current.strings.primaryComponent.languageCode, secondary: current.strings.secondaryComponent?.languageCode)
                present(okUndoController("Debug.ClearCache.Done".i18n(language), current), nil)
            }
        }))
    }
}
private func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}


public func rgDebugController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    let cacheCleanup = RGDebugCacheCleanup()
    
    let arguments = RGItemListArguments<RGDebugToggles, AnyHashable, RGDebugOneFromManySetting, RGDebugDisclosureLink, RGDebugActions>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .forceImmediateShareSheet:
                RGSimpleSettings.shared.forceSystemSharing = value
            case .inputToolbar:
                RGSimpleSettings.shared.inputToolbar = value
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let items: [ActionSheetItem] = []
//        var items: [ActionSheetItem] = []
        
//        switch (setting) {
//        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { _ in
    }, action: { actionType in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch actionType {
            case .clearCache:
                guard !cacheCleanup.isRunning else { return }
                let language = RGLocalizationManager.shared.preferredLocale(primary: presentationData.strings.primaryComponent.languageCode, secondary: presentationData.strings.secondaryComponent?.languageCode)
                let sheet = ActionSheetController(presentationData: presentationData)
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "Debug.ClearCache.Info".i18n(language)),
                        ActionSheetButtonItem(title: "Debug.ClearCache".i18n(language), color: .destructive, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            guard let present = presentControllerImpl else { return }
                            cacheCleanup.start(context: context, present: present)
                        })
                    ]),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
                ])
                presentControllerImpl?(sheet, nil)
            case .clearRegDateCache:
                RGLogger.shared.log("RGDebug", "Regdate cache cleanup init")
                
                /*
                let spinner = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))

                presentControllerImpl?(spinner, nil)
                */
                RGSimpleSettings.shared.regDateCache.drop()
                RGLogger.shared.log("RGDebug", "Regdate cache cleanup succesfull")
                presentControllerImpl?(okUndoController("OK: Regdate cache cleaned", presentationData), nil)
                /*
                Queue.mainQueue().async() { [weak spinner] in
                    spinner?.dismiss()
                }
                */
            case .clearOutgoingTranslationLanguageCache:
                RGLogger.shared.log("RGDebug", "Outgoing translation language cache cleanup init")
                RGSimpleSettings.shared.outgoingLanguageTranslation.drop()
                RGLogger.shared.log("RGDebug", "Outgoing translation language cache cleanup succesfull")
                presentControllerImpl?(okUndoController("OK: Outgoing translation language cache cleaned", presentationData), nil)
        case .flexing:
            #if DEBUG
            FLEXManager.shared.toggleExplorer()
            #endif
        case .fileManager:
            #if DEBUG
            if let dataContainerUrl = rgDataContainerURL() {
                if let fileManager = FLEXFileBrowserController(path: dataContainerUrl.path) {
                    FLEXManager.shared.showExplorer()
                    let flexNavigation = FLEXNavigationController(rootViewController: fileManager)
                    FLEXManager.shared.presentTool({ return flexNavigation })
                }
            } else {
                presentControllerImpl?(UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(title: nil, text: "Empty path", timeout: nil, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ),
                nil)
            }
            #endif

        }
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = RGDebugControllerEntries(presentationData: presentationData)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Regram Debug"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
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
    // Workaround
    let _ = pushControllerImpl
    
    return controller
}

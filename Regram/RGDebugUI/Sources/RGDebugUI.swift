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

// Optional
import RGSimpleSettings
import RGLogging
import RGPayWall
import OverlayStatusController
#if DEBUG
import FLEX
#endif


private enum RGDebugControllerSection: Int32, RGItemListSection {
    case base
    case notifications
}

private enum RGDebugDisclosureLink: String {
    case sessionBackupManager
    case messageFilter
    case debugIAP
}

private enum RGDebugActions: String {
    case flexing
    case fileManager
    case clearRegDateCache
    case clearOutgoingTranslationLanguageCache
    case restorePurchases
    case setIAP
    case resetIAP
}

private enum RGDebugToggles: String {
    case forceImmediateShareSheet
    case legacyNotificationsFix
    case inputToolbar
}


private enum RGDebugOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
}

private typealias RGDebugControllerEntry = RGItemListUIEntry<RGDebugControllerSection, RGDebugToggles, AnyHashable, RGDebugOneFromManySetting, RGDebugDisclosureLink, RGDebugActions>

private func RGDebugControllerEntries(presentationData: PresentationData) -> [RGDebugControllerEntry] {
    var entries: [RGDebugControllerEntry] = []
    
    let id = RGItemListCounter()
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .flexing, text: "FLEX", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .fileManager, text: "FileManager", kind: .generic))
    #endif

    entries.append(.action(id: id.count, section: .base, actionType: .clearRegDateCache, text: "Clear Regdate cache", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .clearOutgoingTranslationLanguageCache, text: "Clear Outgoing Translation cache", kind: .generic))
    entries.append(.toggle(id: id.count, section: .base, settingName: .forceImmediateShareSheet, value: RGSimpleSettings.shared.forceSystemSharing, text: "Force System Share Sheet", enabled: true))
    
    entries.append(.action(id: id.count, section: .base, actionType: .restorePurchases, text: "PayWall.RestorePurchases".i18n(presentationData.strings.baseLanguageCode), kind: .generic))
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .setIAP, text: "Set Pro", kind: .generic))
    #endif
    entries.append(.action(id: id.count, section: .base, actionType: .resetIAP, text: "Reset Pro", kind: .destructive))

    entries.append(.toggle(id: id.count, section: .notifications, settingName: .legacyNotificationsFix, value: RGSimpleSettings.shared.legacyNotificationsFix, text: "[OLD] Fix empty notifications", enabled: true))
    return entries
}
private func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}


public func rgDebugController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = RGItemListArguments<RGDebugToggles, AnyHashable, RGDebugOneFromManySetting, RGDebugDisclosureLink, RGDebugActions>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .forceImmediateShareSheet:
                RGSimpleSettings.shared.forceSystemSharing = value
            case .legacyNotificationsFix:
                RGSimpleSettings.shared.legacyNotificationsFix = value
                RGSimpleSettings.shared.synchronizeShared()
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
            case .clearRegDateCache:
                RGLogger.shared.log("SGDebug", "Regdate cache cleanup init")
                
                /*
                let spinner = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))

                presentControllerImpl?(spinner, nil)
                */
                RGSimpleSettings.shared.regDateCache.drop()
                RGLogger.shared.log("SGDebug", "Regdate cache cleanup succesfull")
                presentControllerImpl?(okUndoController("OK: Regdate cache cleaned", presentationData), nil)
                /*
                Queue.mainQueue().async() { [weak spinner] in
                    spinner?.dismiss()
                }
                */
            case .clearOutgoingTranslationLanguageCache:
                RGLogger.shared.log("SGDebug", "Outgoing translation language cache cleanup init")
                RGSimpleSettings.shared.outgoingLanguageTranslation.drop()
                RGLogger.shared.log("SGDebug", "Outgoing translation language cache cleanup succesfull")
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
        case .restorePurchases:
            presentControllerImpl?(UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: "PayWall.Button.Restoring".i18n(args: context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode), timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            ),
            nil)
            context.sharedContext.RGIAP?.restorePurchases {}
        case .setIAP:
            #if DEBUG
            #endif
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


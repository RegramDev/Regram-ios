// MARK: Regram
import AccountContext
import Display
import Foundation
import ItemListUI
import RGSimpleSettings
import RGStrings
import RGTranscription
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData

private enum RGSTTInputField: Int32 {
    case baseURL
    case endpoint
    case apiKey
    case model
    case language
    case prompt
}

private final class RGSTTSettingsArguments {
    let inputUpdated: (RGSTTInputField, String) -> Void
    let test: () -> Void
    let selectProvider: () -> Void

    init(inputUpdated: @escaping (RGSTTInputField, String) -> Void, test: @escaping () -> Void, selectProvider: @escaping () -> Void) {
        self.inputUpdated = inputUpdated
        self.test = test
        self.selectProvider = selectProvider
    }
}

private enum RGSTTSettingsEntry: ItemListNodeEntry {
    case provider(title: String, value: String)
    case header(section: Int32, text: String)
    case input(field: RGSTTInputField, title: String, text: String, placeholder: String)
    case prompt(text: String, placeholder: String)
    case test(title: String)
    case footer(section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .footer(section, _):
            return section
        case .input, .provider:
            return 0
        case .prompt:
            return 1
        case .test:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .provider: return 5
        case let .header(section, _):
            return section * 100
        case let .input(field, _, _, _):
            return 10 + field.rawValue
        case .prompt:
            return 110
        case .test:
            return 210
        case let .footer(section, _):
            return section * 100 + 90
        }
    }

    static func <(lhs: RGSTTSettingsEntry, rhs: RGSTTSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    var tag: ItemListItemTag? { return nil }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGSTTSettingsArguments
        switch self {
        case let .provider(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: 0, style: .blocks, action: arguments.selectProvider)
        case let .header(section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .input(field, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: field == .apiKey ? .password : .regular(capitalization: false, autocorrection: false), spacing: 8.0, clearType: .onFocus, tag: self.tag, sectionId: 0, textUpdated: { value in
                arguments.inputUpdated(field, value)
            }, action: {})
        case let .prompt(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: 1, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 100.0, textUpdated: { value in
                arguments.inputUpdated(.prompt, value)
            }, tag: self.tag)
        case let .test(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: 2, style: .blocks, action: arguments.test, tag: self.tag)
        case let .footer(section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func rgSTTSettingsErrorText(_ error: Error, language: String) -> String {
    if let error = error as? RGSTTConfigurationError {
        return i18n(error.localizationKey, language)
    }
    if let error = error as? RGSTTKeychainError {
        return "\(i18n("RG.STT.Error.Keychain", language)) (\(error.status))"
    }
    if let error = error as? RGTranscriptionError {
        let key: String
        switch error {
        case .download:
            key = "RG.STT.Error.Download"
        case .invalidAudio:
            key = "RG.STT.Error.InvalidAudio"
        case .fileTooLarge:
            key = "RG.STT.Error.FileTooLarge"
        case .cancelled:
            key = "RG.STT.Error.Cancelled"
        case .timeout:
            key = "RG.STT.Error.Timeout"
        case .invalidResponse:
            key = "RG.STT.Error.InvalidResponse"
        case .noSpeech:
            key = "RG.STT.Error.NoSpeech"
        case .configuration, .http, .network:
            return error.localizedDescription
        }
        return i18n(key, language)
    }
    return error.localizedDescription
}

private func rgSTTSettingsEntries(presentationData: PresentationData, apiKey: String, isTesting: Bool) -> [RGSTTSettingsEntry] {
    let settings = RGSimpleSettings.shared
    let lang = presentationData.strings.baseLanguageCode
    return [
        .header(section: 0, text: i18n("RG.STTSettings", lang)),
        .provider(title: "Settings.Transcription.Backend".i18n(lang), value: "Settings.Transcription.Backend.\(settings.transcriptionBackendEnum.rawValue)".i18n(lang)),
        .input(field: .baseURL, title: i18n("RG.STTBaseURL", lang), text: settings.sttBaseURL, placeholder: RGSTTConfiguration.defaultBaseURL),
        .input(field: .endpoint, title: i18n("RG.STTEndpoint", lang), text: settings.sttEndpoint, placeholder: RGSTTConfiguration.defaultEndpoint),
        .input(field: .apiKey, title: i18n("RG.STTAPIKey", lang), text: apiKey, placeholder: i18n("RG.STTAPIKey.Placeholder", lang)),
        .input(field: .model, title: i18n("RG.STTModel", lang), text: settings.sttModel, placeholder: "gpt-4o-mini-transcribe"),
        .input(field: .language, title: i18n("RG.STTLanguage", lang), text: settings.sttLanguage, placeholder: i18n("RG.STTLanguage.Placeholder", lang)),
        .footer(section: 0, text: i18n("RG.STTSettings.Footer", lang)),
        .header(section: 1, text: i18n("RG.STTPrompt", lang)),
        .prompt(text: settings.sttPrompt, placeholder: i18n("RG.STTPrompt.Placeholder", lang)),
        .footer(section: 1, text: i18n("RG.STTPrompt.Footer", lang)),
        .test(title: i18n(isTesting ? "RG.STT.Cancel" : "RG.STTTest", lang)),
        .footer(section: 2, text: i18n("RG.STTTest.Footer", lang))
    ]
}

public func rgSTTSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let testDisposable = MetaDisposable()
    var isTesting = false
    var apiKey = RGSimpleSettings.shared.sttAPIKey
    var credentialSaveError: Error?
    var presentControllerImpl: ((ViewController) -> Void)?
    let presentResult: (String, String) -> Void = { titleKey, text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: i18n(titleKey, presentationData.strings.baseLanguageCode), text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]))
    }
    let presentError: (String, Error) -> Void = { titleKey, error in
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        presentResult(titleKey, rgSTTSettingsErrorText(error, language: lang))
    }

    let arguments = RGSTTSettingsArguments(inputUpdated: { field, value in
        let settings = RGSimpleSettings.shared
        switch field {
        case .baseURL:
            settings.sttBaseURL = value
        case .endpoint:
            settings.sttEndpoint = value
        case .apiKey:
            apiKey = value
            do {
                try settings.setSTTAPIKey(value)
                credentialSaveError = nil
            } catch {
                if credentialSaveError == nil {
                    presentError("RG.STTSaveFailed", error)
                }
                credentialSaveError = error
            }
        case .model:
            settings.sttModel = value
        case .language:
            settings.sttLanguage = value
        case .prompt:
            settings.sttPrompt = value
        }
    }, test: {
        if isTesting {
            testDisposable.set(nil)
            isTesting = false
            bump()
            return
        }
        if credentialSaveError != nil {
            do {
                try RGSimpleSettings.shared.setSTTAPIKey(apiKey)
                credentialSaveError = nil
            } catch {
                credentialSaveError = error
                presentError("RG.STTSaveFailed", error)
                return
            }
        }
        let configuration: RGSTTConfiguration
        do {
            configuration = try RGSTTConfiguration.current()
        } catch {
            presentError("RG.STTTestFailed", error)
            return
        }
        isTesting = true
        bump()
        testDisposable.set((RGTranscriptionService.shared.test(configuration: configuration)
        |> deliverOnMainQueue).start(next: { text in
            isTesting = false
            bump()
            presentResult("RG.STTTestSucceeded", text)
        }, error: { error in
            isTesting = false
            bump()
            presentError("RG.STTTestFailed", error)
        }))
    }, selectProvider: {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: data)
        let choices: [ActionSheetItem] = RGSimpleSettings.TranscriptionBackend.allCases.map { provider in
            ActionSheetButtonItem(title: "Settings.Transcription.Backend.\(provider.rawValue)".i18n(data.strings.baseLanguageCode), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                RGSimpleSettings.shared.transcriptionBackend = provider.rawValue
                NotificationCenter.default.post(name: RGSimpleSettings.sttSettingsDidChangeNotification, object: nil)
                bump()
            })
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: choices), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
        ])])
        presentControllerImpl?(sheet)
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Settings.Category.transcription", presentationData.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries = rgSTTSettingsEntries(presentationData: presentationData, apiKey: apiKey, isTesting: isTesting)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        testDisposable.dispose()
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root), with: nil)
    }
    return controller
}

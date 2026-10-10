import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import RGTypography
import AccountContext
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import UndoUI

private struct RGSettingsBackupView: View {
    @Environment(\.lang) private var lang
    let export: (Set<RGBackupCategory>) -> Void
    let importFile: (@escaping (Result<RGSettingsBackup, Error>) -> Void) -> Void
    let restore: (RGSettingsBackup?, Set<RGBackupCategory>) -> Void
    @State private var categories = Set(RGBackupCategory.allCases)
    @State private var candidate: RGSettingsBackup?
    @State private var importing = false
    @State private var error = false

    var body: some View {
        List {
            Section(footer: Text("Backup.Notice".i18n(lang))) {
                Button("Backup.Export".i18n(lang)) { export(categories) }.disabled(categories.isEmpty)
                Button("Backup.Import".i18n(lang)) {
                    importing = true
                    importFile { result in
                        importing = false
                        switch result {
                        case let .success(value): candidate = value
                        case let .failure(value): if !(value is CancellationError) { error = true }
                        }
                    }
                }.disabled(importing)
                if importing { ProgressView() }
            }
            Section(header: Text("Backup.Categories".i18n(lang))) {
                ForEach(RGBackupCategory.allCases) { category in
                    Toggle(isOn: Binding(get: { categories.contains(category) }, set: { selected in
                        if selected { categories.insert(category) } else { categories.remove(category) }
                    })) {
                        HStack {
                            Text(category.titleKey.i18n(lang))
                            Spacer()
                            if let candidate { Text("\(candidate.values.keys.filter { RGSettingsBackup.category(for: $0) == category }.count)").foregroundColor(.secondary) }
                        }
                    }
                }
            }
            if let candidate {
                Section(header: Text("Backup.Preview".i18n(lang)), footer: Text("Backup.Fonts.Notice".i18n(lang))) {
                    Text(candidate.createdAt, style: .date)
                    Text("\(candidate.selectedValues(categories: categories).count) " + "Backup.Items".i18n(lang))
                    Button("Backup.Restore".i18n(lang)) { restore(candidate, categories) }.disabled(categories.isEmpty)
                    Button("Backup.CancelPreview".i18n(lang)) { self.candidate = nil }
                }
            }
            Section(footer: Text("Backup.Reset.Notice".i18n(lang))) {
                Button("Backup.Reset".i18n(lang), role: .destructive) { restore(nil, categories) }.disabled(categories.isEmpty)
            }
        }.alert("Backup.Error".i18n(lang), isPresented: $error) { Button("Fonts.OK".i18n(lang), role: .cancel) {} } message: { Text("Backup.Error.Notice".i18n(lang)) }
    }
}

func rgSettingsBackupController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Backup.Title".i18n(data.strings.baseLanguageCode)

    func nativeValues(_ call: CallListSettings, _ experimental: ExperimentalUISettings) -> [String: RGBackupValue] {
        ["native.showContactsTab": .bool(call.showContactsTab), "native.showCallsTab": .bool(call.showTab), "native.foldersAtBottom": .bool(experimental.foldersTabAtBottom), "native.enableVoipTcp": .bool(experimental.enableVoipTcp)]
    }
    func applyNative(_ values: [String: RGBackupValue]) {
        let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            if case let .bool(value)? = values["native.showContactsTab"] { settings.showContactsTab = value }
            if case let .bool(value)? = values["native.showCallsTab"] { settings.showTab = value }
            return settings
        }).startStandalone()
        let _ = updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            if case let .bool(value)? = values["native.foldersAtBottom"] { settings.foldersTabAtBottom = value }
            if case let .bool(value)? = values["native.enableVoipTcp"] { settings.enableVoipTcp = value }
            return settings
        }).startStandalone()
    }
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGSettingsBackupView(export: { [weak controller] categories in
            let _ = (context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings]) |> take(1) |> deliverOnMainQueue).start(next: { shared in
                var values = RGSimpleSettings.shared.exportPreferences(categories: categories).values
                if categories.contains(.appearance) || categories.contains(.media) {
                    let call = shared.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? .defaultSettings
                    let experimental = shared.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? .defaultSettings
                    values.merge(nativeValues(call, experimental).filter { RGSettingsBackup.category(for: $0.key).map(categories.contains) == true }, uniquingKeysWith: { _, new in new })
                }
                guard let controller, var presenter = controller.view.window?.rootViewController else { return }
                while let next = presenter.presentedViewController { presenter = next }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appendingPathComponent(RGSettingsBackup.filename)
                    try RGSettingsBackup(values: values).encoded().write(to: file, options: .atomic)
                    let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                    share.popoverPresentationController?.sourceView = presenter.view
                    share.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                    share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
                    presenter.present(share, animated: true)
                } catch {
                    controller.present(UndoOverlayController(presentationData: data, content: .info(title: nil, text: "Backup.Error".i18n(data.strings.baseLanguageCode), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in false }), in: .window(.root))
                }
            })
        }, importFile: { [weak controller] completion in
            let current = context.sharedContext.currentPresentationData.with { $0 }
            let picker = RGFontDocumentPickerController(theme: current.theme, contentTypes: [.json, .data]) { url in
                guard let url else { completion(.failure(CancellationError())); return }
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= RGSettingsBackup.maximumBytes else { throw RGSettingsBackup.ValidationError.tooLarge }
                    completion(.success(try RGSettingsBackup.decode(Data(contentsOf: url))))
                } catch { completion(.failure(error)) }
            }
            controller?.present(picker, in: .window(.root))
        }, restore: { [weak controller] backup, categories in
            let current = context.sharedContext.currentPresentationData.with { $0 }
            let lang = current.strings.baseLanguageCode
            let sheet = ActionSheetController(presentationData: current)
            sheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: (backup == nil ? "Backup.Reset.Notice" : "Backup.Restore.Notice").i18n(lang)),
                ActionSheetButtonItem(title: (backup == nil ? "Backup.Reset" : "Backup.Restore").i18n(lang), color: .destructive, action: { [weak sheet, weak controller] in
                    sheet?.dismissAnimated()
                    if let backup {
                        let values = backup.selectedValues(categories: categories)
                        RGSimpleSettings.shared.applyPreferences(values)
                        applyNative(values)
                    } else {
                        RGSimpleSettings.shared.applyPreferences([:], resetCategories: categories)
                        applyNative(nativeValues(.defaultSettings, .defaultSettings).filter { RGSettingsBackup.category(for: $0.key).map(categories.contains) == true })
                    }
                    controller?.present(UndoOverlayController(presentationData: current, content: .info(title: nil, text: "Backup.Done".i18n(lang), timeout: nil, customUndoText: "Common.RestartNow".i18n(lang)), elevatedLayout: false, action: { action in if action == .undo { exit(0) }; return true }), in: .window(.root))
                })
            ]), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: current.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
            controller?.present(sheet, in: .window(.root))
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}

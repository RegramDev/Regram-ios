import RGSettingsUI
import Foundation
import UIKit
import SwiftUI
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import RGTypography
import AccountContext
import TelegramPresentationData
import Display

public struct RGFontSettingsView: SwiftUI.View {
    @SwiftUI.Environment(\.lang) private var lang
    @SwiftUI.Environment(\.rgPresentationTheme) private var theme
    @ObservedObject private var store = RGFontStore.shared
    @State private var importedLatin = RGSimpleSettings.shared.fontImportedLatin
    @State private var importedChinese = RGSimpleSettings.shared.fontImportedChinese
    private let presentFontImporter: (@escaping (URL?) -> Void) -> Void
    private let renameFont: (RGImportedFont, @escaping (String) -> Void) -> Void
    private let confirmRemoval: (String, @escaping () -> Void) -> Void
    @State private var importing = false
    @State private var filter = ""
    @State private var script = 0
    @State private var family = RGSimpleSettings.shared.fontConfiguration.family
    @State private var chineseFamily = RGSimpleSettings.shared.fontConfiguration.chineseFamily
    @State private var messages = RGSimpleSettings.shared.fontApplyToMessages
    @State private var interface = RGSimpleSettings.shared.fontApplyToInterface

    private let presentMessage: (String) -> Void

    // Keep the hosted page on the same palette as Telegram's ItemList screens.  The
    // SwiftUI controls below deliberately use these values instead of UIKit's
    // system colors, which otherwise become visibly detached from a tinted theme.
    private var primaryColor: SwiftUI.Color {
        SwiftUI.Color(uiColor: self.theme?.list.itemPrimaryTextColor ?? .label)
    }
    private var secondaryColor: SwiftUI.Color {
        SwiftUI.Color(uiColor: self.theme?.list.itemSecondaryTextColor ?? .secondaryLabel)
    }
    private var accentColor: SwiftUI.Color {
        SwiftUI.Color(uiColor: self.theme?.list.itemAccentColor ?? .systemBlue)
    }
    private var destructiveColor: SwiftUI.Color {
        SwiftUI.Color(uiColor: self.theme?.list.itemDestructiveColor ?? .systemRed)
    }

    public init(initialScript: Int = 0, presentMessage: @escaping (String) -> Void, presentFontImporter: @escaping (@escaping (URL?) -> Void) -> Void, renameFont: @escaping (RGImportedFont, @escaping (String) -> Void) -> Void, confirmRemoval: @escaping (String, @escaping () -> Void) -> Void) {
        self._script = State(initialValue: initialScript)
        self.presentMessage = presentMessage
        self.presentFontImporter = presentFontImporter
        self.renameFont = renameFont
        self.confirmRemoval = confirmRemoval
    }

    private func previewFont(weight: UIFont.Weight = .regular, italic: Bool = false) -> SwiftUI.Font {
        if let font = RGTypography.font(configuration: RGFontConfiguration(family: self.family.rawValue, messages: true, interface: true, chineseFamily: self.chineseFamily.rawValue, importedLatin: self.importedLatin, importedChinese: self.importedChinese, assetsRevision: self.store.revision), size: 19.0, weight: weight, italic: italic) { return SwiftUI.Font(font) }
        var descriptor = UIFont.systemFont(ofSize: 19.0, weight: weight).fontDescriptor
        if italic, let updated = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) { descriptor = updated }
        return SwiftUI.Font(UIFont(descriptor: descriptor, size: 19.0))
    }

    private func download(_ prefix: String?, apply: @escaping () -> Void) {
        guard let prefix, !self.store.isDownloaded(prefix: prefix) else { apply(); return }
        self.store.download(prefix: prefix) { result in
            switch result {
            case .success: apply()
            case .failure: self.showError("Fonts.Download.Error")
            }
        }
    }
    private func showError(_ key: String) {
        self.presentMessage(key.i18n(self.lang))
    }
    private func importFromFiles() {
        guard !self.importing else { return }
        let chinese = self.script == 1
        self.importing = true
        self.presentFontImporter { url in
            guard let url else { self.importing = false; return }
            self.store.importFonts(url: url) { result in
                // The native picker supplies a copy in our container; storage has retained its bytes.
                try? FileManager.default.removeItem(at: url)
                self.importing = false
                switch result {
                case let .success(fonts):
                    guard let font = fonts.first(where: { chinese ? $0.chinese : $0.latin }) ?? fonts.first else { return }
                    if chinese && font.chinese {
                        self.importedChinese = font.id
                    } else if !chinese && font.latin {
                        self.importedLatin = font.id
                    } else if font.chinese {
                        self.script = 1
                        self.importedChinese = font.id
                    } else {
                        self.script = 0
                        self.importedLatin = font.id
                    }
                case .failure:
                    self.showError("Fonts.Import.Error")
                }
            }
        }
    }
    private func importedRows(chinese: Bool) -> some SwiftUI.View {
        ForEach(self.store.imported.filter { (chinese ? $0.chinese : $0.latin) && self.matches($0.title) }) { option in
            Button {
                if chinese { self.importedChinese = option.id } else { self.importedLatin = option.id }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.title)
                            .font(.body)
                            .foregroundColor(self.primaryColor)
                        Text(chinese ? "Fonts.Chinese.Sample".i18n(self.lang) : "The quick brown fox 0123")
                            .font(SwiftUI.Font(RGTypography.font(importedId: option.id, size: 17) ?? UIFont.systemFont(ofSize: 17)))
                            .foregroundColor(self.secondaryColor)
                            .lineLimit(1)
                    }
                    Spacer()
                    if (chinese ? self.importedChinese : self.importedLatin) == option.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(self.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(self.store.downloading != nil || self.importing)
                .contextMenu {
                    Button("Fonts.Rename".i18n(self.lang)) {
                        self.renameFont(option) { title in
                            do { try self.store.rename(id: option.id, title: title) }
                            catch { self.showError("Fonts.Management.Error") }
                        }
                    }
                    Button("Fonts.Delete".i18n(self.lang), role: .destructive) {
                        self.confirmRemoval("Fonts.Delete.Notice") {
                            do {
                                try self.store.remove(id: option.id)
                                if self.importedLatin == option.id { self.importedLatin = ""; self.family = .system }
                                if self.importedChinese == option.id { self.importedChinese = ""; self.chineseFamily = .system }
                            } catch { self.showError("Fonts.Management.Error") }
                        }
                    }
                }
        }
    }

    private func areaRow(_ title: String, id: String, selected: Binding<Bool>) -> some SwiftUI.View {
        Toggle(isOn: selected) {
            Text(title.i18n(self.lang))
                .foregroundColor(self.primaryColor)
        }
        .accessibilityIdentifier(id)
        .accessibilityLabel(title.i18n(self.lang))
        .rgSettingsLink(id == "regram.font.messages" ? "messages" : "interface")
        .accessibilityValue((selected.wrappedValue ? "Fonts.Selected" : "Fonts.Unselected").i18n(self.lang))
    }

    private func matches(_ title: String) -> Bool {
        self.filter.isEmpty || title.localizedCaseInsensitiveContains(self.filter)
    }

    private func fontRow(title: String, sample: String, selected: Bool, available: Bool, font: SwiftUI.Font, action: @escaping () -> Void) -> some SwiftUI.View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(self.primaryColor)
                    Text(available ? sample : "Fonts.Preview.Download".i18n(self.lang))
                        .font(available ? font : .subheadline)
                        .foregroundColor(self.secondaryColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected || !available {
                    Image(systemName: selected ? "checkmark" : "icloud.and.arrow.down")
                        .font(.body)
                        .foregroundColor(selected ? self.accentColor : self.secondaryColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(self.store.downloading != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    public var body: some SwiftUI.View {
        RGSettingsList {
            RGSettingsSection(header: Text("Fonts.Preview".i18n(self.lang))) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Hello, Regram!").font(self.previewFont(weight: .medium))
                        Spacer()
                        Text("Aa · 字").font(.caption).foregroundColor(self.secondaryColor)
                    }
                    Text("Fonts.Sample".i18n(self.lang))
                        .font(self.previewFont())
                        .foregroundColor(self.secondaryColor)
                    HStack(spacing: 18) {
                        Text("Bold 粗体").font(self.previewFont(weight: .bold))
                        Text("Italic 斜体").font(self.previewFont(italic: true))
                    }
                    Divider()
                    Text("0123456789   →  ≠  <=")
                        .font(self.previewFont())
                        .foregroundColor(self.secondaryColor)
                }
                .padding(.vertical, 8)
                .foregroundColor(self.primaryColor)
                .accessibilityIdentifier("regram.font.preview")
            }

            RGSettingsSection(header: Text("Fonts.Areas".i18n(self.lang)), footer: Text((self.messages || self.interface ? "Fonts.Areas.Notice" : "Fonts.NoArea").i18n(self.lang)).foregroundColor(self.secondaryColor)) {
                self.areaRow("Fonts.Messages", id: "regram.font.messages", selected: self.$messages)
                self.areaRow("Fonts.Interface", id: "regram.font.interface", selected: self.$interface)
            }

            if let downloading = self.store.downloading {
                RGSettingsSection(header: Text("Fonts.Storage.Downloads".i18n(self.lang))) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(self.accentColor)
                        Text(downloading)
                            .foregroundColor(self.primaryColor)
                        Spacer()
                        Text("\(Int(self.store.progress * 100))%")
                            .monospacedDigit()
                            .foregroundColor(self.secondaryColor)
                    }
                    ProgressView(value: self.store.progress)
                        .tint(self.accentColor)
                    Button("Fonts.Cancel".i18n(self.lang)) { self.store.cancel() }
                        .foregroundColor(self.accentColor)
                }
            }

            RGSettingsSection {
                Picker("Fonts.Title".i18n(self.lang), selection: self.$script) {
                    Text("Fonts.Latin.Title".i18n(self.lang)).tag(0)
                    Text("Fonts.Chinese.Title".i18n(self.lang)).tag(1)
                }
                .pickerStyle(.segmented)
                .tint(self.accentColor)
                .rgSettingsLink("script")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(self.secondaryColor)
                    TextField("Fonts.Search".i18n(self.lang), text: self.$filter)
                        .foregroundColor(self.primaryColor)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !self.filter.isEmpty {
                        Button { self.filter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(self.secondaryColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if self.script == 0 {
                RGSettingsSection(header: Text("Fonts.Latin.Title".i18n(self.lang))) {
                    ForEach(RGFontFamily.latinChoices.filter { self.matches($0.title.i18n(self.lang)) }, id: \.rawValue) { option in
                        self.fontRow(title: option.title.i18n(self.lang), sample: "The quick brown fox 0123", selected: self.importedLatin.isEmpty && self.family == option, available: self.store.isDownloaded(prefix: option.bundledPrefix), font: SwiftUI.Font(RGTypography.font(family: option, size: 18) ?? UIFont.systemFont(ofSize: 18))) {
                            self.download(option.bundledPrefix) { self.family = option; self.importedLatin = "" }
                        }
                        .accessibilityIdentifier("regram.font.family.\(option.rawValue)")
                    }
                }
                ForEach(["Anthropic", "Google"], id: \.self) { group in
                    let options = RGFontStore.additionalFamilies.filter { $0.group == group && self.matches($0.title) }
                    if !options.isEmpty {
                        RGSettingsSection(header: Text(group)) {
                            ForEach(options) { option in
                                self.fontRow(title: option.title, sample: "The quick brown fox 0123", selected: self.importedLatin == option.selectionId, available: self.store.isDownloaded(prefix: option.id), font: SwiftUI.Font(RGTypography.font(importedId: option.selectionId, size: 18) ?? UIFont.systemFont(ofSize: 18))) {
                                    self.download(option.id) { self.importedLatin = option.selectionId }
                                }
                                .accessibilityIdentifier("regram.font.additional.\(option.id)")
                            }
                        }
                    }
                }
            } else {
                RGSettingsSection(header: Text("Fonts.Chinese.Title".i18n(self.lang))) {
                    ForEach(RGChineseFontFamily.allCases.filter { self.matches($0.title.i18n(self.lang)) }, id: \.rawValue) { option in
                        let prefix: String? = option == .system ? nil : (option == .ibmPlexSansSC ? "IBMPlexSansSC" : "NotoSerifSC")
                        self.fontRow(title: option.title.i18n(self.lang), sample: "Fonts.Chinese.Sample".i18n(self.lang), selected: self.importedChinese.isEmpty && self.chineseFamily == option, available: self.store.isDownloaded(prefix: prefix), font: SwiftUI.Font(RGTypography.chineseFont(family: option, size: 18))) {
                            self.download(prefix) { self.chineseFamily = option; self.importedChinese = "" }
                        }
                        .accessibilityIdentifier("regram.font.chinese.\(option.rawValue)")
                    }
                }
            }

            if !self.store.imported.isEmpty {
                RGSettingsSection(header: Text("Fonts.Imported".i18n(self.lang))) {
                    self.importedRows(chinese: self.script == 1)
                }
            }

            RGSettingsSection(footer: VStack(alignment: .leading, spacing: 4) {
                Text("Fonts.Import.Notice".i18n(self.lang))
                Text("Fonts.Scripts.Notice".i18n(self.lang))
            }.foregroundColor(self.secondaryColor)) {
                Button { self.importFromFiles() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(self.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Fonts.Import".i18n(self.lang))
                                .foregroundColor(self.primaryColor)
                            Text("TTF · OTF · TTC")
                                .font(.footnote)
                                .foregroundColor(self.secondaryColor)
                        }
                        Spacer()
                        if self.importing {
                            ProgressView().tint(self.accentColor)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(self.secondaryColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(self.importing || self.store.downloading != nil)
                .rgSettingsLink("import")
            }

            RGSettingsSection(header: Text("Fonts.Storage".i18n(self.lang)), footer: Text("Fonts.Cloud.Notice".i18n(self.lang)).foregroundColor(self.secondaryColor)) {
                HStack {
                    Text("Fonts.Storage.Downloads".i18n(self.lang))
                        .foregroundColor(self.primaryColor)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: self.store.storageBytes(downloads: true), countStyle: .file))
                        .foregroundColor(self.secondaryColor)
                }
                .rgSettingsLink("storage")
                HStack {
                    Text("Fonts.Imported".i18n(self.lang))
                        .foregroundColor(self.primaryColor)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: self.store.storageBytes(downloads: false), countStyle: .file))
                        .foregroundColor(self.secondaryColor)
                }
                Button("Fonts.ClearDownloads".i18n(self.lang), role: .destructive) {
                    self.confirmRemoval("Fonts.ClearDownloads.Notice") {
                        do {
                            try self.store.clearDownloads()
                            self.family = .system; self.chineseFamily = .system
                            self.importedLatin = RGSimpleSettings.shared.fontImportedLatin
                        } catch { self.showError("Fonts.Management.Error") }
                    }
                }
                .foregroundColor(self.destructiveColor)
                .disabled(self.store.downloading != nil || self.importing)
            }

            RGSettingsSection {
                Button("Fonts.Reset".i18n(self.lang)) {
                    self.store.cancel(); self.family = .system; self.chineseFamily = .system
                    self.importedLatin = ""; self.importedChinese = ""; self.messages = true; self.interface = true
                }
                .foregroundColor(self.destructiveColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("regram.font.reset")
            }
        }
        .onChange(of: self.importedLatin) { RGSimpleSettings.shared.fontImportedLatin = $0 }
        .onChange(of: self.importedChinese) { RGSimpleSettings.shared.fontImportedChinese = $0 }
        .onChange(of: self.family) { RGSimpleSettings.shared.fontFamily = $0.rawValue }
        .onChange(of: self.chineseFamily) { RGSimpleSettings.shared.fontChineseFamily = $0.rawValue }
        .onChange(of: self.messages) { RGSimpleSettings.shared.fontApplyToMessages = $0 }
        .onChange(of: self.interface) { RGSimpleSettings.shared.fontApplyToInterface = $0 }
    }
}

public func rgFontSettingsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Fonts.Title".i18n(data.strings.rgLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGFontSettingsView(initialScript: focusSetting == "chinese" ? 1 : 0, presentMessage: { [weak controller] message in
            guard let controller else { return }
            rgPresentSettingsMessage(context: context, controller: controller, titleKey: "Fonts.Error.Title", text: message)
        }, presentFontImporter: { [weak controller] completion in
            guard let controller else { completion(nil); return }
            let data = context.sharedContext.currentPresentationData.with { $0 }
            // Accept fonts and broadly typed file-provider data; CoreText checks actual contents.
            let picker = RGFontDocumentPickerController(theme: data.theme, completion: completion)
            controller.present(picker, in: .window(.root))
        }, renameFont: { [weak controller] font, apply in
            controller?.push(rgProTextEditorController(context: context, value: font.title, titleKey: "Fonts.Rename", placeholderKey: "Fonts.Rename", noticeKey: "Fonts.Rename.Notice", apply: apply))
        }, confirmRemoval: { [weak controller] notice, apply in
            let data = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: data)
            sheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: notice.i18n(data.strings.rgLanguageCode)),
                ActionSheetButtonItem(title: data.strings.Common_Delete, color: .destructive, action: { [weak sheet] in sheet?.dismissAnimated(); apply() })
            ]), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
            controller?.present(sheet, in: .window(.root))
        })
    })
    controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("fonts", focus: ["latin", "chinese"].contains(focusSetting ?? "") ? "script" : focusSetting), ignoreSafeArea: true))
    return controller
}

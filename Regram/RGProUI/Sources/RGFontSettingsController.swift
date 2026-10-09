import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import RGTypography
import AccountContext
import TelegramPresentationData
import Display

public struct RGFontSettingsView: SwiftUI.View {
    @SwiftUI.Environment(\.lang) private var lang
    @ObservedObject private var store = RGFontStore.shared
    @State private var importedLatin = RGSimpleSettings.shared.fontImportedLatin
    @State private var importedChinese = RGSimpleSettings.shared.fontImportedChinese
    @State private var importer = false
    @State private var importing = false
    @State private var errorPresented = false
    @State private var errorText = ""
    @State private var family = RGSimpleSettings.shared.fontConfiguration.family
    @State private var chineseFamily = RGSimpleSettings.shared.fontConfiguration.chineseFamily
    @State private var messages = RGSimpleSettings.shared.fontApplyToMessages
    @State private var interface = RGSimpleSettings.shared.fontApplyToInterface

    public init() {}

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
        self.errorText = key.i18n(self.lang)
        self.errorPresented = true
    }
    private func importedRows(chinese: Bool) -> some SwiftUI.View {
        ForEach(self.store.imported.filter { chinese ? $0.chinese : $0.latin }) { option in
            Button {
                if chinese { self.importedChinese = option.id } else { self.importedLatin = option.id }
            } label: {
                HStack {
                    Text(option.title).foregroundColor(.primary)
                    Text("Fonts.Imported".i18n(self.lang)).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if (chinese ? self.importedChinese : self.importedLatin) == option.id { Image(systemName: "checkmark") }
                }.padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(self.store.downloading != nil)
        }
    }

    private func areaRow(_ title: String, id: String, selected: Binding<Bool>) -> some SwiftUI.View {
        Button(action: { selected.wrappedValue.toggle() }) {
            HStack {
                Image(systemName: selected.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22.0))
                Text(title.i18n(self.lang)).foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 8.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title.i18n(self.lang))
        .accessibilityValue((selected.wrappedValue ? "Fonts.Selected" : "Fonts.Unselected").i18n(self.lang))
        .accessibilityAddTraits(selected.wrappedValue ? .isSelected : [])
    }

    public var body: some SwiftUI.View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20.0) {
                Text("Fonts.Preview".i18n(self.lang)).font(.headline)
                VStack(alignment: .leading, spacing: 12.0) {
                    Text("Hello, Regram! 中文混排 0123456789").font(self.previewFont())
                    Text("Fonts.Sample".i18n(self.lang)).font(self.previewFont())
                    Text("粗体 Bold → ≠ <= !=").font(self.previewFont(weight: .bold))
                    Text("Italic / 斜体").font(self.previewFont(italic: true))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16.0)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12.0)
                .accessibilityIdentifier("regram.font.preview")

                Text("Fonts.Areas".i18n(self.lang)).font(.headline)
                VStack(spacing: 0.0) {
                    self.areaRow("Fonts.Messages", id: "regram.font.messages", selected: self.$messages)
                    self.areaRow("Fonts.Interface", id: "regram.font.interface", selected: self.$interface)
                }
                Text("Fonts.Areas.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                if !self.messages && !self.interface {
                    Text("Fonts.NoArea".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                }
                Text("Fonts.Cloud.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                if let downloading = self.store.downloading {
                    VStack(alignment: .leading) {
                        Text("\(downloading) · \(Int(self.store.progress * 100))%")
                        ProgressView(value: self.store.progress)
                        Button("Fonts.Cancel".i18n(self.lang)) { self.store.cancel() }
                    }
                }
                Button("Fonts.Import".i18n(self.lang)) { self.importer = true }.disabled(self.importing || self.store.downloading != nil)
                if self.importing { ProgressView() }
                Text("Fonts.Import.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.Latin.Title".i18n(self.lang)).font(.headline)
                ForEach(RGFontFamily.latinChoices, id: \.rawValue) { option in
                    Button(action: { self.download(option.bundledPrefix) { self.family = option; self.importedLatin = "" } }) {
                        HStack {
                            Text(option.title.i18n(self.lang))
                                .font(SwiftUI.Font(RGTypography.font(family: option, size: 17.0) ?? UIFont.systemFont(ofSize: 17.0)))
                                .foregroundColor(.primary)
                            Spacer()
                            if !self.store.isDownloaded(prefix: option.bundledPrefix) { Image(systemName: "icloud.and.arrow.down") }
                            if self.importedLatin.isEmpty && self.family == option { Image(systemName: "checkmark").font(.system(size: 17.0, weight: .semibold)) }
                        }
                        .padding(.vertical, 10.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("regram.font.family.\(option.rawValue)")
                    .disabled(self.store.downloading != nil)
                    .accessibilityAddTraits(self.importedLatin.isEmpty && self.family == option ? .isSelected : [])
                }
                self.importedRows(chinese: false)
                Text("Fonts.Chinese.Title".i18n(self.lang)).font(.headline)
                ForEach(RGChineseFontFamily.allCases, id: \.rawValue) { option in
                    Button(action: { self.download(option == .system ? nil : (option == .ibmPlexSansSC ? "IBMPlexSansSC" : "NotoSerifSC")) { self.chineseFamily = option; self.importedChinese = "" } }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4.0) {
                                Text(option.title.i18n(self.lang)).foregroundColor(.primary)
                                Text("Fonts.Chinese.Sample".i18n(self.lang))
                                    .font(SwiftUI.Font(RGTypography.chineseFont(family: option, size: 17.0)))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if !self.store.isDownloaded(prefix: option == .system ? nil : (option == .ibmPlexSansSC ? "IBMPlexSansSC" : "NotoSerifSC")) { Image(systemName: "icloud.and.arrow.down") }
                            if self.importedChinese.isEmpty && self.chineseFamily == option { Image(systemName: "checkmark").font(.system(size: 17.0, weight: .semibold)) }
                        }
                        .padding(.vertical, 10.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("regram.font.chinese.\(option.rawValue)")
                    .disabled(self.store.downloading != nil)
                    .accessibilityAddTraits(self.importedChinese.isEmpty && self.chineseFamily == option ? .isSelected : [])
                }
                self.importedRows(chinese: true)
                Text("Fonts.Scripts.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.More.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.Fallback".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Button("Fonts.Reset".i18n(self.lang)) { self.store.cancel(); self.family = .system; self.chineseFamily = .system; self.importedLatin = ""; self.importedChinese = ""; self.messages = true; self.interface = true }
                    .accessibilityIdentifier("regram.font.reset")
            }
            .padding(20.0)
        }
        .font(SwiftUI.Font(RGTypography.font(configuration: RGFontConfiguration(family: self.family.rawValue, messages: false, interface: self.interface, chineseFamily: self.chineseFamily.rawValue, importedLatin: self.importedLatin, importedChinese: self.importedChinese, assetsRevision: self.store.revision), size: 17.0) ?? UIFont.systemFont(ofSize: 17.0)))
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .fileImporter(isPresented: self.$importer, allowedContentTypes: ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }, allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            self.importing = true
            self.store.importFont(url: url) { result in
                self.importing = false
                if case .failure = result { self.showError("Fonts.Import.Error") }
            }
        }
        .alert("Fonts.Error.Title".i18n(self.lang), isPresented: self.$errorPresented) { Button("Fonts.OK".i18n(self.lang), role: .cancel) {} } message: { Text(self.errorText) }
        .onChange(of: self.importedLatin) { RGSimpleSettings.shared.fontImportedLatin = $0 }
        .onChange(of: self.importedChinese) { RGSimpleSettings.shared.fontImportedChinese = $0 }
        .onChange(of: self.family) { RGSimpleSettings.shared.fontFamily = $0.rawValue }
        .onChange(of: self.chineseFamily) { RGSimpleSettings.shared.fontChineseFamily = $0.rawValue }
        .onChange(of: self.messages) { RGSimpleSettings.shared.fontApplyToMessages = $0 }
        .onChange(of: self.interface) { RGSimpleSettings.shared.fontApplyToInterface = $0 }
    }
}

public func rgFontSettingsController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.title = "Fonts.Title".i18n(data.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGFontSettingsView() })
    controller.bind(controller: UIHostingController(rootView: content.preferredColorScheme(data.theme.overallDarkAppearance ? .dark : .light).tint(Color(uiColor: data.theme.list.itemAccentColor)), ignoreSafeArea: true))
    return controller
}

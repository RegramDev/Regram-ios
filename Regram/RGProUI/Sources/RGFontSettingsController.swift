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
    @ObservedObject private var store = RGFontStore.shared
    @State private var importedLatin = RGSimpleSettings.shared.fontImportedLatin
    @State private var importedChinese = RGSimpleSettings.shared.fontImportedChinese
    private let presentFontImporter: (@escaping (URL?) -> Void) -> Void
    private let renameFont: (RGImportedFont, @escaping (String) -> Void) -> Void
    private let confirmRemoval: (String, @escaping () -> Void) -> Void
    @State private var importing = false
    @State private var errorPresented = false
    @State private var errorText = ""
    @State private var filter = ""
    @State private var script = 0
    @State private var family = RGSimpleSettings.shared.fontConfiguration.family
    @State private var chineseFamily = RGSimpleSettings.shared.fontConfiguration.chineseFamily
    @State private var messages = RGSimpleSettings.shared.fontApplyToMessages
    @State private var interface = RGSimpleSettings.shared.fontApplyToInterface

    public init(presentFontImporter: @escaping (@escaping (URL?) -> Void) -> Void, renameFont: @escaping (RGImportedFont, @escaping (String) -> Void) -> Void, confirmRemoval: @escaping (String, @escaping () -> Void) -> Void) {
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
        self.errorText = key.i18n(self.lang)
        self.errorPresented = true
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
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(option.title).foregroundColor(.primary)
                        Text(chinese ? "Fonts.Chinese.Sample".i18n(self.lang) : "The quick brown fox 0123")
                            .font(SwiftUI.Font(RGTypography.font(importedId: option.id, size: 17) ?? UIFont.systemFont(ofSize: 17)))
                            .foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if (chinese ? self.importedChinese : self.importedLatin) == option.id { Image(systemName: "checkmark") }
                }.padding(.vertical, 10).contentShape(Rectangle())
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

    private func matches(_ title: String) -> Bool {
        self.filter.isEmpty || title.localizedCaseInsensitiveContains(self.filter)
    }

    private func fontRow(title: String, sample: String, selected: Bool, available: Bool, font: SwiftUI.Font, action: @escaping () -> Void) -> some SwiftUI.View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text(available ? sample : "Fonts.Preview.Download".i18n(self.lang)).font(available ? font : .system(size: 14)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : available ? "circle" : "icloud.and.arrow.down")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(selected ? .accentColor : .secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(self.store.downloading != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    public var body: some SwiftUI.View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("Fonts.Preview".i18n(self.lang), systemImage: "textformat")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                        Spacer()
                        Text("Aa · 字").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                    }
                    Text("Hello, Regram!").font(self.previewFont(weight: .medium))
                    Text("Fonts.Sample".i18n(self.lang)).font(self.previewFont()).foregroundColor(.secondary)
                    HStack(spacing: 18) {
                        Text("Bold 粗体").font(self.previewFont(weight: .bold))
                        Text("Italic 斜体").font(self.previewFont(italic: true))
                    }
                    Divider()
                    Text("0123456789   →  ≠  <=").font(self.previewFont()).foregroundColor(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(22)
                .accessibilityIdentifier("regram.font.preview")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Fonts.Areas".i18n(self.lang)).font(.headline)
                    VStack(spacing: 0) {
                        self.areaRow("Fonts.Messages", id: "regram.font.messages", selected: self.$messages)
                        Divider().padding(.leading, 36)
                        self.areaRow("Fonts.Interface", id: "regram.font.interface", selected: self.$interface)
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(16)
                    Text((self.messages || self.interface ? "Fonts.Areas.Notice" : "Fonts.NoArea").i18n(self.lang))
                        .font(.footnote).foregroundColor(.secondary)
                }

                if let downloading = self.store.downloading {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(downloading, systemImage: "arrow.down.circle")
                            Spacer()
                            Text("\(Int(self.store.progress * 100))%").monospacedDigit()
                        }.font(.subheadline)
                        ProgressView(value: self.store.progress)
                        Button("Fonts.Cancel".i18n(self.lang)) { self.store.cancel() }
                    }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(16)
                }

                VStack(spacing: 14) {
                    Picker("Fonts.Title".i18n(self.lang), selection: self.$script) {
                        Text("Fonts.Latin.Title".i18n(self.lang)).tag(0)
                        Text("Fonts.Chinese.Title".i18n(self.lang)).tag(1)
                    }.pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField(self.lang.hasPrefix("zh") ? "搜索字体" : "Search fonts", text: self.$filter)
                            .autocapitalization(.none).disableAutocorrection(true)
                        if !self.filter.isEmpty { Button { self.filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) } }
                    }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(14)
                }

                if self.script == 0 {
                    LazyVStack(spacing: 10) {
                        ForEach(RGFontFamily.latinChoices.filter { self.matches($0.title.i18n(self.lang)) }, id: \.rawValue) { option in
                            self.fontRow(title: option.title.i18n(self.lang), sample: "The quick brown fox 0123", selected: self.importedLatin.isEmpty && self.family == option, available: self.store.isDownloaded(prefix: option.bundledPrefix), font: SwiftUI.Font(RGTypography.font(family: option, size: 18) ?? UIFont.systemFont(ofSize: 18))) {
                                self.download(option.bundledPrefix) { self.family = option; self.importedLatin = "" }
                            }.accessibilityIdentifier("regram.font.family.\(option.rawValue)")
                        }
                        ForEach(["Anthropic", "Google"], id: \.self) { group in
                            let options = RGFontStore.additionalFamilies.filter { $0.group == group && self.matches($0.title) }
                            if !options.isEmpty {
                                Text(group).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14).padding(.bottom, 2)
                                ForEach(options) { option in
                                    self.fontRow(title: option.title, sample: "The quick brown fox 0123", selected: self.importedLatin == option.selectionId, available: self.store.isDownloaded(prefix: option.id), font: SwiftUI.Font(RGTypography.font(importedId: option.selectionId, size: 18) ?? UIFont.systemFont(ofSize: 18))) {
                                        self.download(option.id) { self.importedLatin = option.selectionId }
                                    }.accessibilityIdentifier("regram.font.additional.\(option.id)")
                                }
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(RGChineseFontFamily.allCases.filter { self.matches($0.title.i18n(self.lang)) }, id: \.rawValue) { option in
                            let prefix: String? = option == .system ? nil : (option == .ibmPlexSansSC ? "IBMPlexSansSC" : "NotoSerifSC")
                            self.fontRow(title: option.title.i18n(self.lang), sample: "Fonts.Chinese.Sample".i18n(self.lang), selected: self.importedChinese.isEmpty && self.chineseFamily == option, available: self.store.isDownloaded(prefix: prefix), font: SwiftUI.Font(RGTypography.chineseFont(family: option, size: 18))) {
                                self.download(prefix) { self.chineseFamily = option; self.importedChinese = "" }
                            }.accessibilityIdentifier("regram.font.chinese.\(option.rawValue)")
                        }
                    }
                }
                if !self.store.imported.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fonts.Imported".i18n(self.lang)).font(.headline)
                        self.importedRows(chinese: self.script == 1)
                    }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(16)
                }
                Button { self.importFromFiles() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fonts.Import".i18n(self.lang)).font(.subheadline.weight(.semibold))
                            Text("TTF · OTF · TTC").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if self.importing { ProgressView() } else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                    }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(16)
                }.buttonStyle(.plain).disabled(self.importing || self.store.downloading != nil)
                Text("Fonts.Import.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.Cloud.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.Scripts.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fonts.Storage".i18n(self.lang)).font(.headline)
                    Text("Fonts.Storage.Downloads".i18n(self.lang) + ": " + ByteCountFormatter.string(fromByteCount: self.store.storageBytes(downloads: true), countStyle: .file))
                    Text("Fonts.Imported".i18n(self.lang) + ": " + ByteCountFormatter.string(fromByteCount: self.store.storageBytes(downloads: false), countStyle: .file))
                    Button("Fonts.ClearDownloads".i18n(self.lang), role: .destructive) {
                        self.confirmRemoval("Fonts.ClearDownloads.Notice") {
                            do {
                                try self.store.clearDownloads()
                                self.family = .system; self.chineseFamily = .system
                                self.importedLatin = RGSimpleSettings.shared.fontImportedLatin
                            } catch { self.showError("Fonts.Management.Error") }
                        }
                    }.disabled(self.store.downloading != nil || self.importing)
                }.font(.footnote).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(16)
                Button("Fonts.Reset".i18n(self.lang)) {
                    self.store.cancel(); self.family = .system; self.chineseFamily = .system
                    self.importedLatin = ""; self.importedChinese = ""; self.messages = true; self.interface = true
                }.font(.footnote).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .accessibilityIdentifier("regram.font.reset")
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Fonts.Title".i18n(data.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGFontSettingsView(presentFontImporter: { [weak controller] completion in
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
                ActionSheetTextItem(title: notice.i18n(data.strings.baseLanguageCode)),
                ActionSheetButtonItem(title: data.strings.Common_Delete, color: .destructive, action: { [weak sheet] in sheet?.dismissAnimated(); apply() })
            ]), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
            controller?.present(sheet, in: .window(.root))
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}

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
    @State private var family = RGSimpleSettings.shared.fontConfiguration.family
    @State private var chineseFamily = RGSimpleSettings.shared.fontConfiguration.chineseFamily
    @State private var messages = RGSimpleSettings.shared.fontApplyToMessages
    @State private var interface = RGSimpleSettings.shared.fontApplyToInterface

    public init() {}

    private func previewFont(weight: UIFont.Weight = .regular, italic: Bool = false) -> SwiftUI.Font {
        if let font = RGTypography.font(configuration: RGFontConfiguration(family: self.family.rawValue, messages: true, interface: true, chineseFamily: self.chineseFamily.rawValue), size: 19.0, weight: weight, italic: italic) { return SwiftUI.Font(font) }
        var descriptor = UIFont.systemFont(ofSize: 19.0, weight: weight).fontDescriptor
        if italic, let updated = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) { descriptor = updated }
        return SwiftUI.Font(UIFont(descriptor: descriptor, size: 19.0))
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
                Text("Fonts.Latin.Title".i18n(self.lang)).font(.headline)
                ForEach(RGFontFamily.latinChoices, id: \.rawValue) { option in
                    Button(action: { self.family = option }) {
                        HStack {
                            Text(option.title.i18n(self.lang))
                                .font(SwiftUI.Font(RGTypography.font(family: option, size: 17.0) ?? UIFont.systemFont(ofSize: 17.0)))
                                .foregroundColor(.primary)
                            Spacer()
                            if self.family == option { Image(systemName: "checkmark").font(.system(size: 17.0, weight: .semibold)) }
                        }
                        .padding(.vertical, 10.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("regram.font.family.\(option.rawValue)")
                    .accessibilityAddTraits(self.family == option ? .isSelected : [])
                }
                Text("Fonts.Chinese.Title".i18n(self.lang)).font(.headline)
                ForEach(RGChineseFontFamily.allCases, id: \.rawValue) { option in
                    Button(action: { self.chineseFamily = option }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4.0) {
                                Text(option.title.i18n(self.lang)).foregroundColor(.primary)
                                Text("Fonts.Chinese.Sample".i18n(self.lang))
                                    .font(SwiftUI.Font(RGTypography.chineseFont(family: option, size: 17.0)))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if self.chineseFamily == option { Image(systemName: "checkmark").font(.system(size: 17.0, weight: .semibold)) }
                        }
                        .padding(.vertical, 10.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("regram.font.chinese.\(option.rawValue)")
                    .accessibilityAddTraits(self.chineseFamily == option ? .isSelected : [])
                }
                Text("Fonts.Scripts.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.More.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.Fallback".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Button("Fonts.Reset".i18n(self.lang)) { self.family = .system; self.chineseFamily = .system; self.messages = true; self.interface = true }
                    .accessibilityIdentifier("regram.font.reset")
            }
            .padding(20.0)
        }
        .font(SwiftUI.Font(RGTypography.font(configuration: RGFontConfiguration(family: self.family.rawValue, messages: false, interface: self.interface, chineseFamily: self.chineseFamily.rawValue), size: 17.0) ?? UIFont.systemFont(ofSize: 17.0)))
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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

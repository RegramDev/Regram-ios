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
    @State private var messages = RGSimpleSettings.shared.fontApplyToMessages
    @State private var interface = RGSimpleSettings.shared.fontApplyToInterface

    public init() {}

    private func previewFont(weight: UIFont.Weight = .regular, italic: Bool = false) -> SwiftUI.Font {
        if let font = RGTypography.font(family: self.family, size: 19.0, weight: weight, italic: italic) { return SwiftUI.Font(font) }
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
                    Text("Hello, Regram! 0123456789").font(self.previewFont())
                    Text("Fonts.Sample".i18n(self.lang)).font(self.previewFont())
                    Text("Aa Bb → ≠ <= !=").font(self.previewFont(weight: .bold))
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
                Text("Fonts.Family".i18n(self.lang)).font(.headline)
                ForEach(RGFontFamily.allCases, id: \.rawValue) { option in
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
                Text("Fonts.More.Notice".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Text("Fonts.Fallback".i18n(self.lang)).font(.footnote).foregroundColor(.secondary)
                Button("Fonts.Reset".i18n(self.lang)) { self.family = .system; self.messages = true; self.interface = true }
                    .accessibilityIdentifier("regram.font.reset")
            }
            .padding(20.0)
        }
        .font(SwiftUI.Font(RGTypography.font(family: self.interface ? self.family : .system, size: 17.0) ?? UIFont.systemFont(ofSize: 17.0)))
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onChange(of: self.family) { RGSimpleSettings.shared.fontFamily = $0.rawValue }
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

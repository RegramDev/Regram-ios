// MARK: Regram
import Foundation
import SwiftUI
import UIKit
import AccountContext
import Display
import RGSwiftUI
import RGSimpleSettings
import RGStrings
import TelegramPresentationData

private struct RGRevokedMarkerView: View {
    @Environment(\.rgSettingsColors) private var colors
    @Environment(\.lang) private var lang
    @State private var marker = RGSimpleSettings.shared.revokedMarker
    let saved: () -> Void
    private var invalidColor: Bool { marker.style != .none && !marker.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && RGRevokedMarker.rgb(marker.color) == nil }
    var body: some View {
        RGSettingsForm {
            RGSettingsSection(footer: Text("RevokedMarker.Notice".i18n(lang))) {
                Picker("RevokedMarker.Style".i18n(lang), selection: $marker.style) {
                    ForEach(RGRevokedMarker.Style.allCases, id: \.self) { style in Text(style.titleKey.i18n(lang)).tag(style) }
                }.pickerStyle(.menu).rgSettingsLink("style")
                if marker.style == .text {
                    TextField("RevokedMarker.Text".i18n(lang), text: $marker.text, prompt: Text("RevokedMarker.DefaultText".i18n(lang)))
                        .onChange(of: marker.text) { value in marker.text = RGRevokedMarker.normalizedText(value) }.rgSettingsLink("text")
                }
                if marker.style != .none {
                    TextField("RevokedMarker.Color".i18n(lang), text: $marker.color, prompt: Text("#RRGGBB"))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().rgSettingsLink("color")
                    if invalidColor { Text("RevokedMarker.InvalidColor".i18n(lang)).font(.footnote).rgSecondaryText() }
                }
            }
            RGSettingsSection(header: Text("RevokedMarker.Preview".i18n(lang))) {
                HStack(spacing: 4) {
                    if let label = marker.label(defaultText: "RevokedMarker.DefaultText".i18n(lang)) {
                        Text(label).foregroundColor(RGRevokedMarker.rgb(marker.color).map { Color(uiColor: UIColor(rgb: $0)) } ?? colors.secondary)
                    }
                    Text("12:34").rgSecondaryText()
                }.font(.footnote)
            }
            Button("NetworkPolicy.Apply".i18n(lang)) { RGSimpleSettings.shared.revokedMarker = marker; saved() }.disabled(invalidColor).rgSettingsLink("apply")
        }
    }
}

public func rgRevokedMarkerController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "RevokedMarker.Title".i18n(data.strings.rgLanguageCode)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) {
        RGRevokedMarkerView(saved: { [weak controller] in guard let controller else { return }; rgPresentSettingsMessage(context: context, controller: controller, titleKey: "RevokedMarker.Title", text: "RevokedMarker.Saved".i18n(controller.lang)) })
    }
    controller.bind(controller: UIHostingController(rootView: view.rgSettingsPage("revokedMarker", focus: focusSetting), ignoreSafeArea: true))
    return controller
}

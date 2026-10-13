import AccountContext
import Display
import Foundation
import LegacyUI
import RGSimpleSettings
import RGStrings
import RGSwiftUI
import SwiftUI

// MARK: Regram
private struct RGLinkPreviewSettingsView: View {
    @Environment(\.lang) private var language: String
    @State private var enabled = RGSimpleSettings.shared.fixLinkPreviews
    @State private var xHost = RGSimpleSettings.shared.linkPreviewXHost
    @State private var instagramHost = RGSimpleSettings.shared.linkPreviewInstagramHost

    private func save() {
        let settings = RGSimpleSettings.shared
        settings.fixLinkPreviews = enabled
        if RGLinkPreviewRules.isValidHost(xHost) { settings.linkPreviewXHost = xHost.trimmingCharacters(in: .whitespacesAndNewlines) }
        if RGLinkPreviewRules.isValidHost(instagramHost) { settings.linkPreviewInstagramHost = instagramHost.trimmingCharacters(in: .whitespacesAndNewlines) }
        NotificationCenter.default.post(name: RGLinkPreviewRules.didChangeNotification, object: nil)
    }

    var body: some View {
        Form {
            Section {
                Toggle("LinkPreview.Repair".i18n(language), isOn: $enabled)
            } footer: {
                Text("LinkPreview.Repair.Notice".i18n(language))
            }
            Section("LinkPreview.Services".i18n(language)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("X / Twitter").font(.caption)
                    TextField(RGLinkPreviewRules.defaultXHost, text: $xHost)
                        .autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instagram").font(.caption)
                    TextField(RGLinkPreviewRules.defaultInstagramHost, text: $instagramHost)
                        .autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL)
                }
                if !RGLinkPreviewRules.isValidHost(xHost) || !RGLinkPreviewRules.isValidHost(instagramHost) {
                    Text("LinkPreview.InvalidHost".i18n(language)).foregroundColor(.red)
                }
                Button("Common.Reset".i18n(language)) {
                    xHost = RGLinkPreviewRules.defaultXHost
                    instagramHost = RGLinkPreviewRules.defaultInstagramHost
                    save()
                }
            }
        }
        .onChange(of: enabled) { _ in save() }
        .onChange(of: xHost) { _ in save() }
        .onChange(of: instagramHost) { _ in save() }
    }
}

public func rgLinkPreviewSettingsController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    let title = "LinkPreview.Repair".i18n(data.strings.baseLanguageCode)
    controller.title = title
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true) { RGLinkPreviewSettingsView() }
    let hosting = UIHostingController(rootView: content, ignoreSafeArea: true)
    controller.bind(controller: hosting)
    controller.bindNativeNavigation(controller: hosting, title: title, backLabel: data.strings.Common_Back)
    return controller
}

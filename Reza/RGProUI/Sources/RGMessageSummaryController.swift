// MARK: Regram — summarize only the selected text after an explicit upload confirmation.
import Foundation
import SwiftUI
import UIKit
import AccountContext
import Display
import TelegramCore
import Postbox
import RGSwiftUI
import RGSimpleSettings
import RGStrings
import RGSettingsUI
import RGGTranslate
import SwiftSignalKit

private struct RGMessageSummaryView: View {
    @Environment(\.lang) private var lang
    @Environment(\.rgSettingsColors) private var colors
    let text: String
    let count: Int
    let configure: () -> Void
    @State private var busy = false
    @State private var result = ""
    @State private var errorText = ""
    @State private var request = MetaDisposable()
    var body: some View {
        RGSettingsList {
            RGSettingsSection(footer: Text("Summary.UploadNotice".i18n(lang))) {
                Text("Summary.Selected".i18n(lang) + " \(count)")
                Text(text).lineLimit(12).foregroundColor(colors.secondary)
                Button("Summary.Configure".i18n(lang), action: configure)
                Button("Summary.Start".i18n(lang), action: start).disabled(busy || text.isEmpty || text.utf8.count > 64000)
                if text.utf8.count > 64000 { Text("Summary.TooLarge".i18n(lang)).foregroundColor(colors.secondary) }
            }
            if busy { RGSettingsSection { ProgressView(); Button("Common.Cancel".i18n(lang)) { request.set(nil); busy = false } } }
            if !errorText.isEmpty { Text(errorText).foregroundColor(colors.destructive) }
            if !result.isEmpty { RGSettingsSection(header: Text("Summary.Result".i18n(lang))) { Text(result).textSelection(.enabled); RGCopyButton("Summary.Copy", value: { result }) } }
        }.onDisappear { request.set(nil); busy = false }
    }
    private func start() {
        guard RGSimpleSettings.shared.messageSummaryEnabled else { return }
        let settings = RGSimpleSettings.shared
        let configuration = RGLLMTranslationConfiguration(format: RGLLMAPIFormat(rawValue: settings.summaryLLMAPIFormat) ?? .openai, baseURL: settings.summaryLLMBaseURL, endpoint: settings.summaryLLMEndpoint, apiKey: settings.summaryLLMAPIKey, model: settings.summaryLLMModel, prompt: settings.summaryLLMPrompt, temperature: Double(settings.summaryLLMTemperatureTenthsValue) / 10)
        guard !configuration.model.isEmpty else { configure(); return }
        errorText = ""; busy = true
        request.set((llmSummarize(text, language: lang, configuration: configuration) |> deliverOnMainQueue).start(next: { value in result = value; busy = false }, error: { error in errorText = error.message; busy = false }))
    }
}

public func rgMessageSummaryController(context: AccountContext, messages: [Message], permitsTimeRange: Bool = false) -> ViewController? {
    guard RGSimpleSettings.shared.messageSummaryEnabled, !messages.isEmpty, messages.count <= (permitsTimeRange ? 5000 : 100), messages.allSatisfy({ $0.id.peerId.namespace != Namespaces.Peer.SecretChat && !$0.containsSecretMedia && !$0.isCopyProtected() }) else { return nil }
    let messages = messages.sorted { $0.index < $1.index }.filter { !$0.rgTextContent.isEmpty }
    guard !messages.isEmpty else { return nil }
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Summary.Action".i18n(data.strings.rgLanguageCode)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) {
        RGMessageSummaryView(text: messages.map(\.rgTextContent).joined(separator: "\n\n---\n\n"), count: messages.count, configure: { [weak controller] in
            (controller?.navigationController as? NavigationController)?.pushViewController(rgLLMSummarySettingsController(context: context))
        })
    }
    controller.bind(controller: UIHostingController(rootView: view, ignoreSafeArea: true))
    return controller
}

// MARK: Regram
import Foundation
import UIKit
import SwiftUI
import SwiftSignalKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import RGGTranslate
import TelegramCore
import AccountContext
import Display

private struct RGLLMSummarySettingsView: View {
    let presentMessage: (String) -> Void
    @Environment(\.lang) private var lang
    @State private var enabled = RGSimpleSettings.shared.messageSummaryEnabled
    @State private var format = RGSimpleSettings.shared.summaryLLMAPIFormat
    @State private var baseURL = RGSimpleSettings.shared.summaryLLMBaseURL
    @State private var endpoint = RGSimpleSettings.shared.summaryLLMEndpoint
    @State private var apiKey = RGSimpleSettings.shared.summaryLLMAPIKey
    @State private var model = RGSimpleSettings.shared.summaryLLMModel
    @State private var prompt = RGSimpleSettings.shared.summaryLLMPrompt
    @State private var temperature = Double(RGSimpleSettings.shared.summaryLLMTemperatureTenthsValue) / 10.0
    @State private var models: [String] = []
    @State private var busy = false
    @State private var request = MetaDisposable()

    private var apiFormat: RGLLMAPIFormat { return RGLLMAPIFormat(rawValue: format) ?? .openai }
    private var configuration: RGLLMTranslationConfiguration {
        return RGLLMTranslationConfiguration(format: apiFormat, baseURL: baseURL, endpoint: endpoint, apiKey: apiKey, model: model, prompt: prompt, temperature: temperature)
    }

    var body: some View {
        RGSettingsForm {
            RGSettingsSection(footer: Text("Summary.EnabledNotice".i18n(lang))) {
                Toggle("Summary.Enabled".i18n(lang), isOn: $enabled).rgSettingsLink("enabled")
                    .onChange(of: enabled) { RGSimpleSettings.shared.messageSummaryEnabled = $0 }
            }
            connectionSection
            modelSection
            promptSection
        }
        .onDisappear { request.set(nil); busy = false }
    }

    private var connectionSection: some View {
        RGSettingsSection(footer: Text("Summary.ConnectionNotice".i18n(lang))) {
            Picker("LLMTranslation.Format".i18n(lang), selection: $format) {
                Text("OpenAI").tag(RGLLMAPIFormat.openai.rawValue)
                Text("Anthropic").tag(RGLLMAPIFormat.anthropic.rawValue)
            }
            .pickerStyle(.menu)
            .rgSettingsLink("format")
            .onChange(of: format) { newValue in
                RGSimpleSettings.shared.summaryLLMAPIFormat = newValue
                // Empty fields use the selected format's defaults; explicit custom URLs stay intact.
                models = []
                request.set(nil)
                busy = false
            }
            RGSettingsTextField("LLMTranslation.BaseURL".i18n(lang), text: $baseURL, placeholder: apiFormat.defaultBaseURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: baseURL) { RGSimpleSettings.shared.summaryLLMBaseURL = $0 }
                .rgSettingsLink("baseURL")
            RGSettingsTextField("LLMTranslation.Endpoint".i18n(lang), text: $endpoint, placeholder: apiFormat.defaultTranslationEndpoint)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: endpoint) { RGSimpleSettings.shared.summaryLLMEndpoint = $0 }
                .rgSettingsLink("endpoint")
            RGSettingsSecureField("LLMTranslation.APIKey".i18n(lang), text: $apiKey)
                .rgSettingsLink("apiKey")
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: apiKey) { value in
                    if !RGSimpleSettings.shared.setSummaryLLMAPIKey(value) {
                        show("LLMTranslation.KeySaveFailed".i18n(lang))
                    }
                }
        }
    }

    private var modelSection: some View {
        RGSettingsSection {
            RGSettingsTextField("LLMTranslation.Model".i18n(lang), text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: model) { RGSimpleSettings.shared.summaryLLMModel = $0 }
                .rgSettingsLink("model")
            if !models.isEmpty {
                Picker("LLMTranslation.SelectModel".i18n(lang), selection: $model) {
                    if !models.contains(model) { Text(model.isEmpty ? "LLMTranslation.SelectModel".i18n(lang) : model).tag(model) }
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            Button("LLMTranslation.FetchModels".i18n(lang)) { fetchModels() }.disabled(busy).rgSettingsLink("fetchModels")
            Button("LLMTranslation.TestModel".i18n(lang)) { testModel() }.disabled(busy || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).rgSettingsLink("testModel")
            if busy { ProgressView() }
        }
    }

    private var promptSection: some View {
        RGSettingsSection(footer: Text("Summary.PromptNotice".i18n(lang))) {
            Text("LLMTranslation.Prompt".i18n(lang))
            RGSettingsTextEditor(text: $prompt).frame(minHeight: 110)
                .onChange(of: prompt) { RGSimpleSettings.shared.summaryLLMPrompt = $0 }
                .rgSettingsLink("prompt")
            HStack {
                Text("LLMTranslation.Temperature".i18n(lang))
                Spacer()
                Text(String(format: "%.1f", temperature)).rgSecondaryText()
            }
            Slider(value: $temperature, in: 0...1, step: 0.1).rgSettingsLink("temperature")
                .onChange(of: temperature) { RGSimpleSettings.shared.summaryLLMTemperatureTenths = Int32(($0 * 10).rounded()) }
        }
    }

    private func show(_ message: String) { presentMessage(message) }

    private func fetchModels() {
        busy = true
        request.set((llmFetchModels(configuration: configuration) |> deliverOnMainQueue).start(next: { values in
            models = values
            busy = false
        }, error: { error in
            busy = false
            show(error.message)
        }))
    }

    private func testModel() {
        busy = true
        request.set((llmTestModel(configuration: configuration) |> deliverOnMainQueue).start(next: { _ in
            busy = false
            show("LLMTranslation.TestSucceeded".i18n(lang))
        }, error: { error in
            busy = false
            show(error.message)
        }))
    }
}

public func rgLLMSummarySettingsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Summary.Title".i18n(data.strings.rgLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGLLMSummarySettingsView(presentMessage: { [weak controller] message in
        guard let controller else { return }
        rgPresentSettingsMessage(context: context, controller: controller, titleKey: "Summary.Title", text: message)
    }) })
    controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("summary", focus: focusSetting), ignoreSafeArea: true))
    return controller
}

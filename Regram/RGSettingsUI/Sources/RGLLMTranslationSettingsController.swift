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

private struct RGLLMTranslationSettingsView: View {
    let presentMessage: (String) -> Void
    @Environment(\.lang) private var lang
    @State private var format = RGSimpleSettings.shared.translationLLMAPIFormat
    @State private var baseURL = RGSimpleSettings.shared.translationLLMBaseURL
    @State private var endpoint = RGSimpleSettings.shared.translationLLMEndpoint
    @State private var apiKey = RGSimpleSettings.shared.translationLLMAPIKey
    @State private var model = RGSimpleSettings.shared.translationLLMModel
    @State private var prompt = RGSimpleSettings.shared.translationLLMPrompt
    @State private var useContext = RGSimpleSettings.shared.translationLLMUseContext
    @State private var temperature = Double(RGSimpleSettings.shared.translationLLMTemperatureTenthsValue) / 10.0
    @State private var models: [String] = []
    @State private var busy = false
    @State private var request = MetaDisposable()

    private var apiFormat: RGLLMAPIFormat { return RGLLMAPIFormat(rawValue: format) ?? .openai }
    private var configuration: RGLLMTranslationConfiguration {
        return RGLLMTranslationConfiguration(format: apiFormat, baseURL: baseURL, endpoint: endpoint, apiKey: apiKey, model: model, prompt: prompt, temperature: temperature)
    }

    var body: some View {
        RGSettingsForm {
            connectionSection
            modelSection
            promptSection
        }
        .onDisappear { request.set(nil); busy = false }
    }

    private var connectionSection: some View {
        RGSettingsSection(footer: Text("LLMTranslation.ConnectionNotice".i18n(lang))) {
            Picker("LLMTranslation.Format".i18n(lang), selection: $format) {
                Text("OpenAI").tag(RGLLMAPIFormat.openai.rawValue)
                Text("Anthropic").tag(RGLLMAPIFormat.anthropic.rawValue)
            }
            .pickerStyle(.menu)
            .rgSettingsLink("format")
            .onChange(of: format) { newValue in
                RGSimpleSettings.shared.translationLLMAPIFormat = newValue
                // Empty fields use the selected format's defaults; explicit custom URLs stay intact.
                models = []
                request.set(nil)
                busy = false
            }
            RGSettingsTextField("LLMTranslation.BaseURL".i18n(lang), text: $baseURL, placeholder: apiFormat.defaultBaseURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: baseURL) { RGSimpleSettings.shared.translationLLMBaseURL = $0 }
                .rgSettingsLink("baseURL")
            RGSettingsTextField("LLMTranslation.Endpoint".i18n(lang), text: $endpoint, placeholder: apiFormat.defaultTranslationEndpoint)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: endpoint) { RGSimpleSettings.shared.translationLLMEndpoint = $0 }
                .rgSettingsLink("endpoint")
            RGSettingsSecureField("LLMTranslation.APIKey".i18n(lang), text: $apiKey)
                .rgSettingsLink("apiKey")
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: apiKey) { value in
                    if !RGSimpleSettings.shared.setTranslationLLMAPIKey(value) {
                        show("LLMTranslation.KeySaveFailed".i18n(lang))
                    }
                }
        }
    }

    private var modelSection: some View {
        RGSettingsSection {
            RGSettingsTextField("LLMTranslation.Model".i18n(lang), text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: model) { RGSimpleSettings.shared.translationLLMModel = $0 }
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
        RGSettingsSection(footer: Text("LLMTranslation.PromptNotice".i18n(lang))) {
            Text("LLMTranslation.Prompt".i18n(lang))
            RGSettingsTextEditor(text: $prompt).frame(minHeight: 110)
                .onChange(of: prompt) { RGSimpleSettings.shared.translationLLMPrompt = $0 }
                .rgSettingsLink("prompt")
            Toggle("LLMTranslation.UseContext".i18n(lang), isOn: $useContext)
                .onChange(of: useContext) { RGSimpleSettings.shared.translationLLMUseContext = $0 }
                .rgSettingsLink("useContext")
            HStack {
                Text("LLMTranslation.Temperature".i18n(lang))
                Spacer()
                Text(String(format: "%.1f", temperature)).rgSecondaryText()
            }
            Slider(value: $temperature, in: 0...1, step: 0.1).rgSettingsLink("temperature")
                .onChange(of: temperature) { RGSimpleSettings.shared.translationLLMTemperatureTenths = Int32(($0 * 10).rounded()) }
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

public func rgLLMTranslationSettingsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "LLMTranslation.Title".i18n(data.strings.rgLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGLLMTranslationSettingsView(presentMessage: { [weak controller] message in
        guard let controller else { return }
        rgPresentSettingsMessage(context: context, controller: controller, titleKey: "LLMTranslation.Title", text: message)
    }) })
    controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("llm", focus: focusSetting), ignoreSafeArea: true))
    return controller
}

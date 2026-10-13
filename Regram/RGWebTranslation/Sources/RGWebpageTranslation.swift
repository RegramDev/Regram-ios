// MARK: Regram — translate the current page with the selected message translation service.
import AccountContext
import Foundation
import RGStrings
import RGSimpleSettings
import TranslateUI
import NaturalLanguage
import SwiftSignalKit
import TelegramCore
import WebKit
import UIKit

public final class RGWebpageTranslation {
    public private(set) var running = false
    public private(set) var translated = false
    private weak var webView: WKWebView?
    private let context: AccountContext
    private let request = MetaDisposable()
    private var generation = UUID()
    private var timeout: DispatchWorkItem?
    private var backgroundObserver: NSObjectProtocol?

    public init(webView: WKWebView, context: AccountContext) {
        self.webView = webView
        self.context = context
        self.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restore()
        }
    }
    deinit { request.dispose(); timeout?.cancel(); if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) } }

    public func navigationChanged() {
        generation = UUID(); request.set(nil); timeout?.cancel(); timeout = nil
        running = false; translated = false
    }
    public func restore() {
        navigationChanged()
        evaluate(RGWebTranslationScript.restore) { _, _ in }
    }
    private func evaluate(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        guard let webView else { return }
        if #available(iOS 14.0, *) {
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                switch result { case let .success(value): completion(value, nil); case let .failure(error): completion(nil, error) }
            }
        } else {
            webView.evaluateJavaScript(script, completionHandler: completion)
        }
    }
    public func start(error showError: @escaping (String) -> Void) {
        guard !running, let scheme = webView?.url?.scheme?.lowercased(), ["https", "http"].contains(scheme) else { return }
        if RGSimpleSettings.shared.translationBackendEnum == .system {
            guard #available(iOS 18.0, *) else { showError("Browser.Translation.SystemUnavailable"); return }
            if engineExperimentalInternalTranslationService == nil, let hostView = context.sharedContext.mainWindow?.hostView {
                engineExperimentalInternalTranslationService = ExperimentalInternalTranslationServiceImpl(view: hostView.containerView)
            }
        }
        restore()
        let id = UUID(); generation = id; running = true
        evaluate(RGWebTranslationScript.collect) { [weak self] value, error in
            guard let self, self.generation == id else { return }
            guard error == nil, let texts = value as? [String], !texts.isEmpty else {
                self.running = false; showError("Browser.Translation.NoText"); return
            }
            // Bound work on exceptionally large pages before uploading any content.
            guard texts.count <= 2000, texts.reduce(0, { $0 + $1.utf8.count }) <= 500_000 else {
                self.running = false; showError("Browser.Translation.TooLarge"); return
            }
            let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
            let language = RGLocalizationManager.shared.preferredLocale(primary: strings.primaryComponent.languageCode, secondary: strings.secondaryComponent?.languageCode)
            self.translate(texts, index: 0, language: language, generation: id, error: showError)
        }
    }
    private func translationSignal(_ texts: [String], language: String) -> Signal<[String], TranslationError> {
        if RGSimpleSettings.shared.translationBackendEnum == .system {
            guard let service = engineExperimentalInternalTranslationService, let source = NLLanguageRecognizer.dominantLanguage(for: texts.joined(separator: "\n"))?.rawValue else { return .fail(.generic) }
            if source.lowercased() == language.lowercased() { return .single(texts) }
            let keyed = Dictionary(uniqueKeysWithValues: texts.enumerated().map { (AnyHashable($0.offset), $0.element) })
            return service.translate(texts: keyed, fromLang: source, toLang: language)
            |> castError(TranslationError.self)
            |> mapToSignal { result -> Signal<[String], TranslationError> in
                guard let result else { return .fail(.generic) }
                let values = texts.indices.compactMap { result[AnyHashable($0)] }
                return values.count == texts.count ? .single(values) : .fail(.generic)
            }
        }
        return context.engine.messages.translate(texts: texts.map { ($0, []) }, toLang: language) |> map { $0.map { $0.0 } }
    }
    private func translate(_ texts: [String], index: Int, language: String, generation id: UUID, error showError: @escaping (String) -> Void) {
        guard generation == id else { return }
        guard texts.indices.contains(index) else { running = false; translated = true; return }
        timeout?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id else { return }
            self.request.set(nil); self.timeout = nil; self.running = false; self.generation = UUID()
            showError("Browser.Translation.Failed")
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: deadline)
        let batch = Array(texts[index..<min(texts.count, index + 8)])
        request.set((translationSignal(batch, language: language) |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, self.generation == id else { return }
            self.timeout?.cancel(); self.timeout = nil
            let scripts = value.enumerated().compactMap { RGWebTranslationScript.apply(index: index + $0.offset, translation: $0.element) }
            guard value.count == batch.count, scripts.count == batch.count else {
                self.running = false; showError("Browser.Translation.Failed"); return
            }
            self.evaluate(scripts.joined(separator: ";\n")) { [weak self] _, error in
                guard let self, self.generation == id else { return }
                if error != nil { self.running = false; showError("Browser.Translation.Failed"); return }
                self.translated = true
                // Schedule the next request after the current disposable has been installed.
                DispatchQueue.main.async { [weak self] in self?.translate(texts, index: index + batch.count, language: language, generation: id, error: showError) }
            }
        }, error: { [weak self] _ in
            guard let self, self.generation == id else { return }
            self.timeout?.cancel(); self.timeout = nil; self.running = false
            showError("Browser.Translation.Failed")
        }))
    }
}

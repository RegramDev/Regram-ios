import Foundation
import CoreML
import NaturalLanguage

public struct RGAdSemanticResult {
    public let predictions: [RGAdPrediction]
    public let buttonIds: Set<String>
    public let threshold: Double
    public let entireMessage: Bool
    public init(predictions: [RGAdPrediction] = [], buttonIds: Set<String> = [], threshold: Double = 1, entireMessage: Bool = false) {
        self.predictions = predictions; self.buttonIds = buttonIds; self.threshold = threshold; self.entireMessage = entireMessage
    }
}

/// A bundled, trained transformer. No network calls, message uploads, or self-training on guesses.
/// Call on a background queue. The shared bounded cache also reuses repeated channel footers.
public final class RGAdSemanticClassifier {
    public static let shared = RGAdSemanticClassifier()
    private struct Manifest: Decodable {
        let version: Int
        let sequenceLength: Int
        let threshold: Double
        let labels: [String]
    }
    private struct Loaded { let model: MLModel; let tokenizer: RGAdTokenizer; let threshold: Double }
    private let lock = NSLock()
    private let resourceDirectory: URL?
    private var loaded: Loaded?
    private var retryAfter: TimeInterval = 0
    private var scores: [String: Double] = [:]
    private var order: [String] = []

    public init(resourceDirectory: URL? = nil) { self.resourceDirectory = resourceDirectory }

    private func resource(_ name: String, _ ext: String) -> URL? {
        if let resourceDirectory {
            let url = resourceDirectory.appendingPathComponent(name).appendingPathExtension(ext)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources") { return url }
        #endif
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    private func load() throws -> Loaded {
        if let loaded { return loaded }
        guard ProcessInfo.processInfo.systemUptime >= retryAfter,
              let manifestURL = resource("RGAdModel", "json"), let vocabularyURL = resource("RGAdVocabulary", "txt") else { throw RGAdFilterError.invalidModel }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1, manifest.labels == ["content", "promotion"], manifest.threshold.isFinite,
              (0.8...0.9999).contains(manifest.threshold) else { throw RGAdFilterError.invalidModel }
        let tokenizer = try RGAdTokenizer(vocabulary: String(contentsOf: vocabularyURL, encoding: .utf8), sequenceLength: manifest.sequenceLength)
        let modelURL: URL
        if let compiled = resource("RGAdSemantic", "mlmodelc") { modelURL = compiled }
        else if let raw = resource("RGAdSemantic", "mlmodel") { modelURL = try MLModel.compileModel(at: raw) }
        else { throw RGAdFilterError.invalidModel }
        let configuration = MLModelConfiguration()
        if #available(iOS 16.0, macOS 13.0, *) { configuration.computeUnits = .cpuAndNeuralEngine }
        else { configuration.computeUnits = .all }
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["input_ids"] != nil,
              model.modelDescription.inputDescriptionsByName["attention_mask"] != nil,
              model.modelDescription.outputDescriptionsByName["probabilities"] != nil else { throw RGAdFilterError.invalidModel }
        let value = Loaded(model: model, tokenizer: tokenizer, threshold: manifest.threshold)
        loaded = value
        return value
    }

    private func probability(_ text: String, using value: Loaded) throws -> Double? {
        let key = RGAdTokenizer.normalize(text)
        if let cached = scores[key] { return cached }
        guard key.count >= 4, let windows = value.tokenizer.windows(key), windows.count <= 8 else { return nil }
        var minimum = 1.0
        for window in windows {
            let ids = try MLMultiArray(shape: [1, NSNumber(value: value.tokenizer.sequenceLength)], dataType: .int32)
            let mask = try MLMultiArray(shape: ids.shape, dataType: .int32)
            for (index, token) in window.enumerated() { ids[index] = NSNumber(value: token); mask[index] = token == 0 ? 0 : 1 }
            let features = try MLDictionaryFeatureProvider(dictionary: ["input_ids": MLFeatureValue(multiArray: ids), "attention_mask": MLFeatureValue(multiArray: mask)])
            let output = try value.model.prediction(from: features)
            guard let probabilities = output.featureValue(for: "probabilities")?.multiArrayValue, probabilities.count == 2 else { throw RGAdFilterError.invalidPrediction }
            let score = probabilities[1].doubleValue
            guard score.isFinite, (0...1).contains(score) else { throw RGAdFilterError.invalidPrediction }
            minimum = min(minimum, score)
        }
        if order.count >= 2048 { scores.removeValue(forKey: order.removeFirst()) }
        order.append(key); scores[key] = minimum
        return minimum
    }

    /// Public for the same production engine's conversion and physical-device regression harness.
    public func probability(_ text: String) throws -> Double? {
        lock.lock(); defer { lock.unlock() }
        return try probability(text, using: load())
    }

    /// Preflight from the settings queue so a missing/broken model is visible to the user.
    public func prepareModel() -> Bool {
        lock.lock(); defer { lock.unlock() }
        do { return try probability("本机模型运行检测", using: load()) != nil }
        catch { retryAfter = ProcessInfo.processInfo.systemUptime + 60; return false }
    }

    public func predict(_ input: RGAdInput) -> RGAdSemanticResult {
        guard input.text.utf16.count <= 65_536, input.entities.count <= 2048,
              input.buttons.count <= 128, input.buttons.flatMap({ $0 }).count <= 128,
              input.buttons.flatMap({ $0 }).allSatisfy({ $0.title.utf16.count <= 1024 }) else { return RGAdSemanticResult() }
        // This checkpoint was trained on Chinese, not multilingual illustration captions.
        // Out-of-domain confidence is not evidence: keep those messages for explicit rules.
        let language = NLLanguageRecognizer.dominantLanguage(for: RGAdTokenizer.normalize(input.text))
        guard language == .simplifiedChinese || language == .traditionalChinese else { return RGAdSemanticResult() }
        lock.lock(); defer { lock.unlock() }
        do {
            let value = try load()
            let source = input.text as NSString
            var predictions: [RGAdPrediction] = []
            let paragraphs = RGAdFilter.semanticRanges(input.text)
            let blocks = RGAdFilter.contextRanges(input.text)
            // Work is bounded and off the UI queue. Oversized messages remain intact.
            guard paragraphs.count <= 128 else { return RGAdSemanticResult() }
            var hasContent = false
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            let substantive = paragraphs.filter { RGAdTokenizer.normalize(source.substring(with: $0.nsRange)).count >= 4 }
            var blockScores: [RGAdRange: Double] = [:]
            for block in blocks {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { return RGAdSemanticResult() }
                if let score = try probability(source.substring(with: block.nsRange), using: value) { blockScores[block] = score }
            }
            for range in paragraphs {
                if ProcessInfo.processInfo.systemUptime > deadline { hasContent = true; break }
                guard !input.entities.contains(where: { $0.kind == .code && $0.range.intersects(range) }) else { hasContent = true; continue }
                let text = source.substring(with: range.nsRange)
                let score = try probability(text, using: value)
                let quoted = input.entities.contains { $0.kind == .quote && $0.range.intersects(range) }
                var contextualLead = true
                if range == substantive.first, substantive.count >= 3, let score, score >= value.threshold {
                    // Headlines can resemble solicitations in isolation. Require the beginning
                    // of the following body to agree before removing a lead sentence.
                    let lead = RGAdRange(range.lower, substantive[2].upper)
                    contextualLead = (try probability(source.substring(with: lead.nsRange), using: value) ?? 0) >= value.threshold
                }
                // A sentence about prices/payments may resemble a solicitation in isolation.
                // Its complete paragraph must agree before any sentence can be cut.
                let contextualBlock = blocks.first(where: { $0.contains(range) }).flatMap { blockScores[$0] } ?? 0
                if let score, score >= value.threshold, contextualBlock >= value.threshold, !quoted, contextualLead {
                    predictions.append(RGAdPrediction(range: range, confidence: score))
                }
                let length = RGAdTokenizer.normalize(text).unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count
                if score == nil && length >= 8 {
                    hasContent = true
                } else if (score ?? 1) <= 0.2, length >= 32 || range == substantive.first && length >= 4 {
                    // A price list or feature line is not an independent normal paragraph.
                    // Require a substantive body sentence (or the opening content) and its
                    // complete blank-line block to agree before vetoing a whole ad. A short
                    // generic feature in the middle cannot override the complete-message model.
                    if let block = blocks.first(where: { $0.contains(range) }),
                       let context = try probability(source.substring(with: block.nsRange), using: value), context <= 0.2 {
                        hasContent = true
                    }
                }
            }
            // Decorative banners carry little textual meaning. Remove them only inside a
            // complete footer: a divider, at least two independently promotional lines, no
            // normal/unknown line, and agreement on all substantive footer text together.
            // This also keeps linked dividers atomic instead of guessing their destination.
            let lines = RGAdFilter.paragraphRanges(input.text)
            for (index, line) in lines.enumerated() where RGAdFilter.isSeparator(source.substring(with: line.nsRange)) {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                let footer = RGAdRange(line.lower, source.length)
                guard footer.upper - footer.lower <= 2048, lines.count - index <= 32,
                      !input.entities.contains(where: { [.code, .quote].contains($0.kind) && $0.range.intersects(footer) }) else { continue }
                var scores: [Double] = []
                var footerTexts: [String] = []
                var complete = true
                for candidate in lines[(index + 1)...] {
                    guard ProcessInfo.processInfo.systemUptime <= deadline else { complete = false; break }
                    let text = source.substring(with: candidate.nsRange)
                    if !RGAdTokenizer.normalize(text).unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { continue }
                    guard let score = try probability(text, using: value), score >= value.threshold else { complete = false; break }
                    scores.append(score)
                    footerTexts.append(text)
                }
                if complete, scores.count >= 2, let score = try probability(footerTexts.joined(separator: "\n"), using: value), score >= value.threshold {
                    predictions.append(RGAdPrediction(range: footer, confidence: min(score, scores.min() ?? score)))
                    break
                }
            }
            // A whole promotional card is hidden only when its complete text agrees and there
            // is no substantive preserved sentence. A movie/news body vetoes this decision.
            var entireMessage = false
            if !hasContent, !substantive.isEmpty, blockScores.values.contains(where: { $0 >= value.threshold }), ProcessInfo.processInfo.systemUptime <= deadline {
                var whole = try probability(input.text, using: value) ?? 0
                if whole < max(0.99, value.threshold), (3...32).contains(blocks.count) {
                    // Long cards exceed one transformer window. Price/features must be read
                    // with their heading and call to action, rather than treating a generic
                    // device-support line as an independent message. Require TWO independently
                    // confident promotional blocks, then agreement for EVERY contextual block.
                    let texts = blocks.map { source.substring(with: $0.nsRange) }
                    var anchors: [String] = []
                    for text in texts where ProcessInfo.processInfo.systemUptime <= deadline {
                        if let score = try probability(text, using: value), score >= value.threshold { anchors.append(text) }
                    }
                    if anchors.count >= 2, let anchor = anchors.min(by: { $0.utf16.count < $1.utf16.count }),
                       let lead = texts.first, RGAdTokenizer.normalize(lead).count <= 96 {
                        var contextual = 1.0
                        for text in texts {
                            guard ProcessInfo.processInfo.systemUptime <= deadline else { contextual = 0; break }
                            if RGAdTokenizer.normalize(text).count < 4 { continue }
                            let view = [lead, text, anchor].joined(separator: "\n")
                            contextual = min(contextual, try probability(view, using: value) ?? 0)
                            if contextual < max(0.99, value.threshold) { break }
                        }
                        whole = max(whole, contextual)
                    }
                }
                if whole >= max(0.99, value.threshold), ProcessInfo.processInfo.systemUptime <= deadline {
                    predictions.append(RGAdPrediction(range: RGAdRange(0, input.text.utf16.count), confidence: whole))
                    entireMessage = true
                }
            }
            var buttons = Set<String>()
            for button in input.buttons.flatMap({ $0 }) {
                if entireMessage { buttons.insert(button.id) }
                else if ProcessInfo.processInfo.systemUptime <= deadline, let score = try probability(button.title, using: value), score >= value.threshold { buttons.insert(button.id) }
            }
            return RGAdSemanticResult(predictions: predictions, buttonIds: buttons, threshold: value.threshold, entireMessage: entireMessage)
        } catch {
            retryAfter = ProcessInfo.processInfo.systemUptime + 60
            return RGAdSemanticResult() // Keep uncertain/unavailable-model content; explicit corrections still work.
        }
    }
}

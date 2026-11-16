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
        // Core ML's ANE path differs from the validated export in probability parity.
        // This strict classifier needs stable probabilities at its decision threshold. Keep inference on the CPU;
        // bounded background work and the shared score cache avoid repeated footer inference.
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["input_ids"] != nil,
              model.modelDescription.inputDescriptionsByName["attention_mask"] != nil,
              model.modelDescription.outputDescriptionsByName["probabilities"] != nil else { throw RGAdFilterError.invalidModel }
        let value = Loaded(model: model, tokenizer: tokenizer, threshold: manifest.threshold)
        loaded = value
        return value
    }

    private func probability(_ text: String, using value: Loaded, minimumLength: Int = 4) throws -> Double? {
        let key = RGAdTokenizer.normalize(text)
        guard key.count >= minimumLength else { return nil }
        if let cached = scores[key] { return cached }
        guard let windows = value.tokenizer.windows(key), windows.count <= 8 else { return nil }
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
        // Foreign names/hashtags can dominate a movie post's language guess. In that case
        // assess Chinese fragments independently, while preserving the foreign body as a whole.
        func supportsLanguage(_ text: String) -> Bool {
            let normalized = RGAdTokenizer.normalize(text)
            let language = NLLanguageRecognizer.dominantLanguage(for: normalized)
            if language == .simplifiedChinese || language == .traditionalChinese { return true }
            // Technical Chinese often lists Latin model/protocol names. Admit substantial
            // Chinese prose even when those names dominate the statistical language guess.
            // This is eligibility only; every scored window and content guard still applies.
            if language == .japanese || language == .korean || normalized.unicodeScalars.contains(where: {
                (0x3041...0x3096).contains($0.value) || (0x30a1...0x30fa).contains($0.value) || (0xac00...0xd7a3).contains($0.value)
            }) { return false }
            let han = normalized.unicodeScalars.filter { (0x3400...0x9fff).contains($0.value) }.count
            let letters = normalized.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            return han >= 24 && han * 4 >= letters
        }
        let wholeLanguageSupported = supportsLanguage(input.text)
        guard wholeLanguageSupported || (input.text + input.buttons.flatMap({ $0 }).map(\.title).joined()).unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) else { return RGAdSemanticResult() }
        lock.lock(); defer { lock.unlock() }
        do {
            let value = try load()
            let source = input.text as NSString
            func hasSemanticWords(_ range: RGAdRange) -> Bool {
                let destinations = input.entities.filter { entity in
                    [.link, .mention].contains(entity.kind) && entity.range.lower < entity.range.upper && range.contains(entity.range)
                        && RGAdFilter.normalizedTarget(source.substring(with: entity.range.nsRange)) != nil
                }.sorted { $0.range.lower < $1.range.lower }
                var text = "", cursor = range.lower
                for entity in destinations {
                    if cursor < entity.range.lower { text += source.substring(with: NSRange(location: cursor, length: entity.range.lower - cursor)) }
                    cursor = max(cursor, entity.range.upper)
                }
                if cursor < range.upper { text += source.substring(with: NSRange(location: cursor, length: range.upper - cursor)) }
                return RGAdTokenizer.normalize(text).unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
            }
            var predictions: [RGAdPrediction] = []
            let navigationRows = RGAdFilter.navigationRows(input)
            let navigation = Set(navigationRows.values.flatMap { $0 })
            let paragraphs = (RGAdFilter.semanticRanges(input.text).filter { range in
                !navigationRows.keys.contains(where: { $0.intersects(range) })
            } + Array(navigation)).sorted { $0.lower < $1.lower }
            let blocks = RGAdFilter.contextRanges(input.text)
            // Work is bounded and off the UI queue. Oversized messages remain intact.
            guard paragraphs.count <= 128 else { return RGAdSemanticResult() }
            var hasContent = !wholeLanguageSupported
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            let substantive = paragraphs.filter { RGAdTokenizer.normalize(source.substring(with: $0.nsRange)).count >= 4 }
            var blockScores: [RGAdRange: Double] = [:]
            for block in blocks {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { return RGAdSemanticResult() }
                if !wholeLanguageSupported && !supportsLanguage(source.substring(with: block.nsRange)) { continue }
                if let score = try probability(source.substring(with: block.nsRange), using: value) { blockScores[block] = score }
            }
            for range in paragraphs {
                if ProcessInfo.processInfo.systemUptime > deadline { hasContent = true; break }
                guard !input.entities.contains(where: { $0.kind == .code && $0.range.intersects(range) && !RGAdFilter.isInlineCodeLabel($0, source: source) }) else { hasContent = true; continue }
                let text = source.substring(with: range.nsRange)
                // A bare URL/handle cannot express promotional intent independently. Its
                // destination may still be removed with a fully classified card or footer.
                if !hasSemanticWords(range) { continue }
                if !wholeLanguageSupported && !supportsLanguage(text) { continue }
                let score = try probability(text, using: value, minimumLength: navigation.contains(range) ? 2 : 4)
                let quoted = input.entities.contains { $0.kind == .quote && $0.range.intersects(range) }
                var contextualLead = true
                if range == substantive.first, substantive.count >= 3, let score, score >= value.threshold {
                    // Headlines can resemble solicitations in isolation. Require the beginning
                    // of the following body to agree before removing a lead sentence.
                    let lead = RGAdRange(range.lower, blocks.count >= 2 ? blocks[1].upper : substantive[1].upper)
                    contextualLead = (try probability(source.substring(with: lead.nsRange), using: value) ?? 0) >= value.threshold
                }
                // A sentence about prices/payments may resemble a solicitation in isolation.
                // Its complete paragraph must agree before any sentence can be cut.
                let blockIndex = blocks.firstIndex(where: { $0.contains(range) })
                let contextualBlock = blockIndex.flatMap { blockScores[blocks[$0]] } ?? 0
                var contextualNeighbors = true
                let length = RGAdTokenizer.normalize(text).unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count
                if let score, score >= value.threshold, blocks.count > 1, let blockIndex,
                   !input.entities.contains(where: { [.link, .mention].contains($0.kind) && $0.range.intersects(range) }) {
                    // A price, launch announcement or release-status sentence in an article needs
                    // surrounding agreement. Linked calls to action are assessed in their own block.
                    let neighbors = RGAdRange(blocks[max(0, blockIndex - 1)].lower, blocks[min(blocks.count - 1, blockIndex + 1)].upper)
                    contextualNeighbors = (try probability(source.substring(with: neighbors.nsRange), using: value) ?? 0) >= value.threshold
                    if length < 48, (try probability(input.text, using: value) ?? 0) <= 0.2 { contextualNeighbors = false }
                }
                // A linked article/document title is not evidence of selling by itself.
                // When both the surrounding prose and complete post strongly say content,
                // preserve a standalone descriptive reference despite its isolated score.
                // Bare destinations, short menu items and long promotional paragraphs keep
                // their existing evaluation paths.
                if let score, score >= value.threshold, (12...48).contains(length),
                   !navigation.contains(range), blocks.count > 1, let blockIndex,
                   let reference = input.entities.first(where: { entity in
                       entity.kind == .link && range.contains(entity.range)
                       && RGAdFilter.normalizedTarget(source.substring(with: entity.range.nsRange)) == nil
                       && RGAdTokenizer.normalize(source.substring(with: entity.range.nsRange)) == RGAdTokenizer.normalize(text)
                   }), (try probability(input.text, using: value) ?? 1) <= 0.2 {
                    let neighbors = RGAdRange(blocks[max(0, blockIndex - 1)].lower, blocks[min(blocks.count - 1, blockIndex + 1)].upper)
                    if (try probability(source.substring(with: neighbors.nsRange), using: value) ?? 1) <= 0.2 {
                        // A matching promotional action supports the original high-score cut;
                        // normal "read more"/resource buttons do not supply that evidence.
                        let target = RGAdFilter.normalizedTarget(reference.value)
                        var promotionalAction = false
                        for button in input.buttons.flatMap({ $0 }) where target != nil && RGAdFilter.normalizedTarget(button.target) == target {
                            guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                            if (try probability(button.title, using: value) ?? 0) >= 0.5 { promotionalAction = true; break }
                        }
                        if !promotionalAction { contextualNeighbors = false }
                    }
                }
                let linkedCaption = length < 48 && input.entities.contains(where: { [.link, .mention].contains($0.kind) && range.contains($0.range) })
                if let score, score >= value.threshold, (contextualBlock >= value.threshold || linkedCaption), !quoted, contextualLead, contextualNeighbors {
                    predictions.append(RGAdPrediction(range: range, confidence: score))
                }
                if score == nil && length >= 8 {
                    hasContent = true
                } else if (score ?? 1) <= 0.2, length >= 64 {
                    // A price list or feature line is not an independent normal paragraph.
                    // Require a substantive body sentence and its
                    // complete blank-line block to agree before vetoing a whole ad. A short
                    // generic feature in the middle cannot override the complete-message model.
                    if let block = blocks.first(where: { $0.contains(range) }),
                       let context = try probability(source.substring(with: block.nsRange), using: value), context <= 0.2 {
                        hasContent = true
                    }
                }
            }
            // Very short menu labels need their adjacent link's context. Extend only an
            // already confident promotional menu item, with independent agreement on the
            // combined labels. Low-scoring navigation titles cannot join the removed span.
            for units in navigationRows.values {
                for (index, range) in units.enumerated() {
                    guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                    let text = source.substring(with: range.nsRange)
                    guard (2...3).contains(RGAdTokenizer.normalize(text).count),
                          let shortScore = try probability(text, using: value, minimumLength: 2), shortScore >= 0.99 else { continue }
                    for neighborIndex in [index - 1, index + 1] where units.indices.contains(neighborIndex) {
                        let neighbor = units[neighborIndex]
                        guard let known = predictions.first(where: { $0.range.contains(neighbor) && $0.confidence >= value.threshold }) else { continue }
                        let combined = RGAdRange(min(range.lower, neighbor.lower), max(range.upper, neighbor.upper))
                        if let score = try probability(source.substring(with: combined.nsRange), using: value), score >= value.threshold {
                            predictions.append(RGAdPrediction(range: combined, confidence: min(score, known.confidence)))
                        }
                    }
                }
            }
            // Decorative banners carry little textual meaning. Remove them only inside a
            // complete footer: a divider, independently promotional text, no
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
                    // Bare contact destinations and their decorative logos have no standalone
                    // semantic meaning. They may join an already delimited commercial footer,
                    // but cannot establish that footer's promotional verdict themselves.
                    if !hasSemanticWords(candidate) { continue }
                    if !wholeLanguageSupported && !supportsLanguage(text) { complete = false; break }
                    guard let score = try probability(text, using: value), score >= value.threshold else { complete = false; break }
                    scores.append(score)
                    footerTexts.append(text)
                }
                if complete, !scores.isEmpty, let score = try probability(footerTexts.joined(separator: "\n"), using: value), score >= value.threshold {
                    predictions.append(RGAdPrediction(range: footer, confidence: min(score, scores.min() ?? score)))
                    break
                }
            }
            // A whole promotional card is hidden only when its complete text agrees and there
            // is no substantive preserved sentence. A movie/news body vetoes this decision.
            var entireMessage = false
            var projectionThreshold = value.threshold
            let hasBodyBeyondNavigation = navigation.isEmpty || substantive.contains(where: { !navigation.contains($0) })
            if !hasContent, !substantive.isEmpty, hasBodyBeyondNavigation, ProcessInfo.processInfo.systemUptime <= deadline {
                let whole = try probability(input.text, using: value) ?? 0
                let meaningfulBlocks = blocks.filter { hasSemanticWords($0) && RGAdTokenizer.normalize(source.substring(with: $0.nsRange)).count >= 4 }
                // Long all-commercial cards can have slightly lower minimum-window scores.
                // Require complete-text agreement, EVERY meaningful block >= .99, and two
                // independently high-scoring blocks before using this whole-card threshold.
                // No individual sentence receives the relaxed threshold.
                if whole >= 0.99, meaningfulBlocks.count >= 2,
                   meaningfulBlocks.allSatisfy({ (blockScores[$0] ?? 0) >= 0.99 }),
                   meaningfulBlocks.filter({ (blockScores[$0] ?? 0) >= value.threshold }).count >= 2 {
                    projectionThreshold = min(value.threshold, 0.99)
                }
                if whole >= max(0.99, projectionThreshold), ProcessInfo.processInfo.systemUptime <= deadline {
                    predictions.append(RGAdPrediction(range: RGAdRange(0, input.text.utf16.count), confidence: whole))
                    entireMessage = true
                }
            }
            var buttons = Set<String>()
            for button in input.buttons.flatMap({ $0 }) {
                if entireMessage { buttons.insert(button.id) }
                else if ProcessInfo.processInfo.systemUptime <= deadline, supportsLanguage(button.title), let score = try probability(button.title, using: value), score >= value.threshold { buttons.insert(button.id) }
            }
            return RGAdSemanticResult(predictions: predictions, buttonIds: buttons, threshold: entireMessage ? projectionThreshold : value.threshold, entireMessage: entireMessage)
        } catch {
            retryAfter = ProcessInfo.processInfo.systemUptime + 60
            return RGAdSemanticResult() // Keep uncertain/unavailable-model content; explicit corrections still work.
        }
    }
}

import Foundation
import CoreML
import NaturalLanguage

public struct RGAdSemanticResult {
    public let predictions: [RGAdPrediction]
    public let buttonIds: Set<String>
    public let threshold: Double
    public let entireMessage: Bool
    public let completed: Bool
    public let promotionalQuotes: [RGAdRange]
    public init(predictions: [RGAdPrediction] = [], buttonIds: Set<String> = [], threshold: Double = 1, entireMessage: Bool = false, completed: Bool = true, promotionalQuotes: [RGAdRange] = []) {
        self.predictions = predictions; self.buttonIds = buttonIds; self.threshold = threshold; self.entireMessage = entireMessage
        self.completed = completed
        self.promotionalQuotes = promotionalQuotes
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
    private struct Loaded {
        let model: MLModel; let tokenizer: RGAdTokenizer; let threshold: Double
        let ids: MLMultiArray; let mask: MLMultiArray; let features: MLDictionaryFeatureProvider
    }
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
        guard ProcessInfo.processInfo.systemUptime >= retryAfter else { throw RGAdFilterError.invalidModel }
        if let loaded { return loaded }
        guard let manifestURL = resource("RGAdModel", "json"), let vocabularyURL = resource("RGAdVocabulary", "txt") else { throw RGAdFilterError.invalidModel }
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
        // The classifier lock serializes all predictions. Reuse these fixed-size input tensors
        // and the feature provider instead of allocating/boxing 256 NSNumber values per window.
        let ids = try MLMultiArray(shape: [1, NSNumber(value: tokenizer.sequenceLength)], dataType: .int32)
        let mask = try MLMultiArray(shape: ids.shape, dataType: .int32)
        let features = try MLDictionaryFeatureProvider(dictionary: ["input_ids": MLFeatureValue(multiArray: ids), "attention_mask": MLFeatureValue(multiArray: mask)])
        let value = Loaded(model: model, tokenizer: tokenizer, threshold: manifest.threshold, ids: ids, mask: mask, features: features)
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
            guard window.count == value.ids.count, value.mask.count == value.ids.count else { throw RGAdFilterError.invalidPrediction }
            let ids = value.ids.dataPointer.assumingMemoryBound(to: Int32.self)
            let mask = value.mask.dataPointer.assumingMemoryBound(to: Int32.self)
            for (index, token) in window.enumerated() { ids[index] = token; mask[index] = token == 0 ? 0 : 1 }
            let output = try value.model.prediction(from: value.features)
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
        catch {
            if ProcessInfo.processInfo.systemUptime >= retryAfter { retryAfter = ProcessInfo.processInfo.systemUptime + 60 }
            return false
        }
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
            return han >= (normalized.count <= 128 ? 4 : 24) && han * 4 >= letters
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
            var promotionalQuotes: [RGAdRange] = []
            let navigationRows = RGAdFilter.navigationRows(input)
            let navigation = Set(navigationRows.values.flatMap { $0 })
            let paragraphs = (RGAdFilter.semanticRanges(input.text, entities: input.entities).filter { range in
                !navigationRows.keys.contains(where: { $0.intersects(range) })
            } + Array(navigation)).sorted { $0.lower < $1.lower }
            let blocks = RGAdFilter.contextRanges(input.text)
            // Work is bounded and off the UI queue. Oversized messages remain intact.
            guard paragraphs.count <= 128 else { return RGAdSemanticResult() }
            var hasContent = !wholeLanguageSupported
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            let substantive = paragraphs.filter { RGAdTokenizer.normalize(source.substring(with: $0.nsRange)).count >= 4 }
            let interactive = input.buttons.flatMap { $0 }.filter { $0.target == nil }.count >= 2
            let disclosedProse = input.entities.contains(where: { $0.kind == .code }) && !RGAdDisclosure.ranges(input).isEmpty
            var blockScores: [RGAdRange: Double] = [:]
            for block in blocks {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { return RGAdSemanticResult(completed: false) }
                if !wholeLanguageSupported && !supportsLanguage(source.substring(with: block.nsRange)) { continue }
                if let score = try probability(source.substring(with: block.nsRange), using: value) { blockScores[block] = score }
            }
            // Several independently normal blocks must not become a whole advertisement just
            // because their combined text contains a short sponsorship footer.
            if blockScores.count >= 2, blockScores.values.allSatisfy({ $0 <= 0.2 }) { hasContent = true }
            // A normal introduction followed immediately by a quotation can be a report,
            // example or filter test. The quoted sales pitch must not turn that explanation
            // into a whole-message advertisement, even with a separate sponsorship menu.
            let introductoryQuote: RGAdRange? = {
                guard blocks.count >= 2, let first = blocks.first, (blockScores[first] ?? 1) <= 0.2,
                      RGAdTokenizer.normalize(source.substring(with: first.nsRange)).unicodeScalars.filter({ (0x3400...0x9fff).contains($0.value) }).count >= 12,
                      !input.entities.contains(where: { [.quote, .code].contains($0.kind) && $0.range.intersects(first) }),
                      input.entities.contains(where: { [.quote, .code].contains($0.kind) && blocks[1].contains($0.range) }) else { return nil }
                return blocks[1]
            }()
            if introductoryQuote != nil { hasContent = true }
            for range in paragraphs {
                if ProcessInfo.processInfo.systemUptime > deadline { hasContent = true; break }
                guard !input.entities.contains(where: { $0.kind == .code && $0.range.intersects(range) && !RGAdFilter.isInlineCodeLabel($0, source: source)
                    && !(disclosedProse && RGAdDisclosure.isProseBlock($0, source: source)) }) else { hasContent = true; continue }
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
                if let score, score >= value.threshold, (4...48).contains(length), (length >= 12 || contextualBlock <= 0.2),
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
                            if let actionScore = try probability(button.title, using: value), actionScore >= 0.5 {
                                promotionalAction = true
                                // A standalone sponsor link can also precede the article.
                                // A separately classified action to the identical destination
                                // confirms its role without borrowing the normal article's intent.
                                if actionScore >= max(0.99, value.threshold), contextualBlock >= max(0.99, value.threshold) {
                                    contextualLead = true
                                }
                                break
                            }
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
                    if let blockIndex, (blockScores[blocks[blockIndex]] ?? 1) <= 0.2 {
                        let neighbors = RGAdRange(blocks[max(0, blockIndex - 1)].lower, blocks[min(blocks.count - 1, blockIndex + 1)].upper)
                        // Disclaimers inside a paid offer can be normal in isolation. Require
                        // surrounding context too before treating one as independent content.
                        if (try probability(source.substring(with: neighbors.nsRange), using: value) ?? 0) <= 0.2 {
                            // A paid card can put its feature list or risk disclosure several
                            // blocks after its offer. Keep the preceding offer in the model's
                            // context, without allowing a later advertisement to consume an
                            // earlier article. Both the complete post and the offer/body pair
                            // must independently agree at the stricter whole-card threshold.
                            var belongsToOffer = false
                            if ProcessInfo.processInfo.systemUptime <= deadline,
                               let offer = blocks.prefix(blockIndex).last(where: { (blockScores[$0] ?? 0) >= max(0.99, value.threshold) }),
                               (try probability(input.text, using: value) ?? 0) >= max(0.99, value.threshold) {
                                let context = source.substring(with: offer.nsRange) + "\n\n" + source.substring(with: blocks[blockIndex].nsRange)
                                belongsToOffer = (try probability(context, using: value) ?? 0) >= max(0.99, value.threshold)
                            }
                            if !belongsToOffer { hasContent = true }
                        }
                    }
                }
                // Search results and interactive bot menus can mix unrelated short entries.
                // A confidently normal header/body and opaque actions veto whole-message
                // deletion; each commercial entry is still classified independently.
                if interactive, (score ?? 1) <= 0.2, length >= 8,
                   contextualBlock <= 0.2 || input.entities.contains(where: { $0.kind == .link && range.contains($0.range) }) { hasContent = true }
                // A short tutorial/resource introduction with its own bare URL is
                // still meaningful content. When the later promotional blocks link
                // elsewhere, their greater length must not erase this introduction.
                if range == substantive.first, (score ?? 1) <= 0.2, length >= 12,
                   let blockIndex, contextualBlock <= 0.2, blocks.indices.contains(blockIndex + 1) {
                    let reference = blocks[blockIndex + 1]
                    if !hasSemanticWords(reference) {
                        let referenceTargets = Set(input.entities.compactMap { entity -> String? in
                            guard entity.kind == .link, reference.contains(entity.range) else { return nil }
                            return RGAdFilter.normalizedTarget(entity.value ?? source.substring(with: entity.range.nsRange))
                        })
                        if !referenceTargets.isEmpty, blocks.dropFirst(blockIndex + 2).contains(where: { block in
                            guard (blockScores[block] ?? 0) >= value.threshold else { return false }
                            return input.entities.contains { entity in
                                guard entity.kind == .link, block.contains(entity.range),
                                      let target = RGAdFilter.normalizedTarget(entity.value ?? source.substring(with: entity.range.nsRange)) else { return false }
                                return !referenceTargets.contains(target)
                            }
                        }) { hasContent = true }
                    }
                }
            }
            // A blank-line paragraph can be one complete commercial solicitation split over
            // several lines. Require every substantive line, the full block, and an attached
            // destination to agree. This removes the solicitation with its contact line while
            // retaining neighbouring release notes, news, and mixed navigation rows.
            for block in blocks {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                guard let score = blockScores[block], score >= value.threshold,
                      !input.entities.contains(where: { [.code, .quote].contains($0.kind) && $0.range.intersects(block) }),
                      input.entities.contains(where: { [.link, .mention].contains($0.kind) && block.contains($0.range) }) else { continue }
                let units = paragraphs.filter { block.contains($0) && hasSemanticWords($0) && RGAdTokenizer.normalize(source.substring(with: $0.nsRange)).count >= 4 }
                guard units.count >= 2, !units.contains(where: { navigation.contains($0) }) else { continue }
                var minimum = score
                for unit in units {
                    guard ProcessInfo.processInfo.systemUptime <= deadline,
                          let part = try probability(source.substring(with: unit.nsRange), using: value) else { minimum = 0; break }
                    minimum = min(minimum, part)
                    if minimum < value.threshold { break }
                }
                if minimum >= value.threshold { predictions.append(RGAdPrediction(range: block, confidence: minimum)) }
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
            // Telegram blockquotes are also used to style sponsorship footers. Only treat a
            // complete quoted block as commercial when every substantive line agrees, two
            // adjacent menu links independently promote it, and a trained, explicitly framed
            // context input classifies the quoted part as promotion. It distinguishes a styled
            // sponsorship footer from a report/test quoting identical commercial wording.
            for (index, block) in blocks.enumerated() where index > 0 && index + 1 < blocks.count {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                guard let score = blockScores[block], score >= max(0.99, value.threshold),
                      block != introductoryQuote,
                      input.entities.contains(where: { $0.kind == .quote && block.contains($0.range) }),
                      !input.entities.contains(where: { $0.kind == .code && $0.range.intersects(block) }),
                      let menu = navigationRows.first(where: { blocks[index + 1].contains($0.key) })?.value,
                      menu.filter({ unit in predictions.contains(where: { $0.range.contains(unit) && $0.confidence >= max(0.99, value.threshold) }) }).count >= 2 else { continue }
                let units = paragraphs.filter { block.contains($0) && hasSemanticWords($0) && RGAdTokenizer.normalize(source.substring(with: $0.nsRange)).count >= 4 }
                guard units.count >= 2 else { continue }
                var allCommercial = true
                for unit in units {
                    guard ProcessInfo.processInfo.systemUptime <= deadline,
                          (try probability(source.substring(with: unit.nsRange), using: value) ?? 0) >= value.threshold else { allCommercial = false; break }
                }
                let context = source.substring(with: blocks[index - 1].nsRange)
                let quote = source.substring(with: block.nsRange).trimmingCharacters(in: .whitespacesAndNewlines)
                let commercialMenu = menu.filter { unit in predictions.contains(where: { $0.range.contains(unit) && $0.confidence >= max(0.99, value.threshold) }) }
                    .map { source.substring(with: $0.nsRange).trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
                // Keep this framing in sync with Training/quote_context.py. A short context
                // fits the native window; longer ambiguous quotations remain protected.
                guard quote.count <= 64 else { continue }
                let framed = "上文：" + String(context.trimmingCharacters(in: .whitespacesAndNewlines).suffix(32))
                    + "\n引用：" + quote + "\n后续入口：" + String(commercialMenu.prefix(16))
                if allCommercial, ProcessInfo.processInfo.systemUptime <= deadline,
                   let contextual = try probability(framed, using: value), contextual >= max(0.99, value.threshold) {
                    predictions.append(RGAdPrediction(range: block, confidence: min(score, contextual)))
                    promotionalQuotes.append(block)
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
                // Callback actions (verification/moderation/polls) are opaque and
                // cannot be inferred as ads from their short label alone.
                else if RGAdFilter.normalizedTarget(button.target) != nil, ProcessInfo.processInfo.systemUptime <= deadline, supportsLanguage(button.title), let score = try probability(button.title, using: value), score >= value.threshold { buttons.insert(button.id) }
            }
            // A short stock/offer card may express its purchase intent in the attached action.
            // Require every action to be independently promotional, joint-text agreement,
            // and no confidently normal body. Mixed menus, quotes and normal sharing keep
            // their own content even when an unrelated promotional button is removed.
            let actions = input.buttons.flatMap { $0 }
            if !entireMessage, !actions.isEmpty, actions.count <= 4,
               (4...64).contains(RGAdTokenizer.normalize(input.text).count),
               !input.entities.contains(where: { [.code, .quote].contains($0.kind) }),
               actions.allSatisfy({ RGAdFilter.normalizedTarget($0.target) != nil && buttons.contains($0.id) }),
               ProcessInfo.processInfo.systemUptime <= deadline,
               (try probability(input.text, using: value) ?? 0) >= 0.5 {
                let combined = input.text + "\n" + actions.map(\.title).joined(separator: "\n")
                if let score = try probability(combined, using: value), score >= max(0.99, value.threshold) {
                    predictions.append(RGAdPrediction(range: RGAdRange(0, source.length), confidence: score))
                    entireMessage = true
                }
            }
            return RGAdSemanticResult(predictions: predictions, buttonIds: buttons, threshold: entireMessage ? projectionThreshold : value.threshold, entireMessage: entireMessage, completed: ProcessInfo.processInfo.systemUptime <= deadline, promotionalQuotes: promotionalQuotes)
        } catch {
            if ProcessInfo.processInfo.systemUptime >= retryAfter { retryAfter = ProcessInfo.processInfo.systemUptime + 60 }
            return RGAdSemanticResult(completed: false) // Unavailable is not a normal-message verdict.
        }
    }
}

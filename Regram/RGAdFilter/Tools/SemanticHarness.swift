import Foundation

// This harness executes the shipping tokenizer, Core ML engine and projection on macOS/iOS.
// Fixtures and reports may contain real messages: callers must put them in ignored build-input.
enum RGAdSemanticChecks {
    struct Vector: Decodable { let text: String; let ids: [Int32]; let probability: Double }
    struct Case: Decodable { let id: String; let text: String; let label: Int }
    struct Segment: Decodable { let text: String; let label: Int; let range: RGAdRange }
    struct Post: Decodable { let id: String; let kind: String; let input: RGAdInput; let segments: [Segment] }
    static func run(resources: URL, fixtures: URL, output: URL) throws {
        let classifier = RGAdSemanticClassifier(resourceDirectory: resources)
        let tokenizer = try RGAdTokenizer(vocabulary: String(contentsOf: resources.appendingPathComponent("RGAdVocabulary.txt"), encoding: .utf8))
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("RGAdModel.json"))) as! [String: Any]
        let threshold = manifest["threshold"] as! Double
        var report: [String: Any] = ["threshold": threshold, "system": ProcessInfo.processInfo.operatingSystemVersionString, "modelSHA256": manifest["modelSHA256"]!]
        let start = ProcessInfo.processInfo.systemUptime
        guard classifier.prepareModel() else { throw RGAdFilterError.invalidModel }
        report["coldLoadMilliseconds"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
        var latencies: [Double] = []
        func score(_ text: String) throws -> Double {
            let start = ProcessInfo.processInfo.systemUptime
            let p = try classifier.probability(text) ?? -1
            latencies.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            return p
        }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: fixtures.appendingPathComponent("conversion-vectors.json")) {
            let vectors = try decoder.decode([Vector].self, from: data)
            var maxError = 0.0
            for vector in vectors {
                // Python conversion vectors deliberately truncate at 126 tokens. Compare the
                // matching first native window; probability parity uses untruncated short cases.
                guard tokenizer.windows(vector.text)?.first == vector.ids else { throw RGAdFilterError.unsupportedTokenizer }
                if let tokens = tokenizer.tokens(vector.text), tokens.count <= 126 {
                    maxError = max(maxError, abs(try score(vector.text) - vector.probability))
                }
            }
            guard maxError < 0.01 else { throw RGAdFilterError.invalidPrediction }
            report["parity"] = ["vectors": vectors.count, "maxProbabilityError": maxError]
        }
        if let data = try? Data(contentsOf: fixtures.appendingPathComponent("guard-holdout.json")) {
            let cases = try decoder.decode([Case].self, from: data)
            var rows: [[String: Any]] = [], tp = 0, tn = 0, fp = 0, fn = 0
            for item in cases {
                let p = try score(item.text), positive = p >= threshold
                if item.label == 1 { if positive { tp += 1 } else { fn += 1 } }
                else { if positive { fp += 1 } else { tn += 1 } }
                rows.append(["id": item.id, "label": item.label, "probability": p])
            }
            report["externalCases"] = ["tp": tp, "tn": tn, "fp": fp, "fn": fn, "rows": rows]
        }
        if let data = try? Data(contentsOf: fixtures.appendingPathComponent("channel-evaluation.json")) {
            let posts = try decoder.decode([Post].self, from: data)
            var rows: [[String: Any]] = []
            for post in posts {
                let predictionStarted = ProcessInfo.processInfo.systemUptime
                let semantic = classifier.predict(post.input)
                let projection = try RGAdPolicy.project(post.input, semantic: semantic)
                let predictionMilliseconds = (ProcessInfo.processInfo.systemUptime - predictionStarted) * 1000
                var retainedNormal = 0, removedAds = 0, removedNormal = 0, retainedAds = 0, partialAds = 0
                var segments: [[String: Any]] = []
                let source = post.input.text as NSString
                for segment in post.segments {
                    var cursor = segment.range.lower, kept = "", removed = ""
                    for range in projection.removedRanges where range.intersects(segment.range) {
                        let lower = max(segment.range.lower, range.lower), upper = min(segment.range.upper, range.upper)
                        if cursor < lower { kept += source.substring(with: NSRange(location: cursor, length: lower - cursor)) }
                        removed += source.substring(with: NSRange(location: lower, length: upper - lower))
                        cursor = max(cursor, upper)
                    }
                    if cursor < segment.range.upper { kept += source.substring(with: NSRange(location: cursor, length: segment.range.upper - cursor)) }
                    let cut = !removed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let fullyRemoved = kept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if segment.label == 0 { if cut { removedNormal += 1 } else { retainedNormal += 1 } }
                    else { if fullyRemoved { removedAds += 1 } else { retainedAds += 1; if cut { partialAds += 1 } } }
                    segments.append(["label": segment.label, "probability": try score(segment.text), "cut": cut, "fullyRemoved": fullyRemoved, "range": [segment.range.lower, segment.range.upper]])
                }
                let contextScores = try RGAdFilter.contextRanges(post.input.text).map { range -> [String: Any] in
                    ["range": [range.lower, range.upper], "probability": try score((post.input.text as NSString).substring(with: range.nsRange))]
                }
                rows.append(["id": post.id, "kind": post.kind, "disposition": projection.disposition.rawValue, "semanticWhole": semantic.entireMessage, "wholeProbability": try score(post.input.text), "contextScores": contextScores, "normalKept": retainedNormal, "normalCut": removedNormal, "adCut": removedAds, "adKept": retainedAds, "adPartial": partialAds, "segments": segments, "buttonsKept": projection.buttons.flatMap { $0 }.map(\.id), "projection": projection.text, "predictionMilliseconds": predictionMilliseconds])
            }
            report["posts"] = rows
        }
        latencies.sort()
        report["latencyIncludesCacheHits"] = true
        report["latencyMilliseconds"] = ["count": latencies.count, "median": latencies.isEmpty ? 0 : latencies[latencies.count / 2], "p95": latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }
}

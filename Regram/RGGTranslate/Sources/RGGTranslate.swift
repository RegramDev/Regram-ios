import Foundation
import SwiftSignalKit
import SwiftSoup

public enum TranslateFetchError {
    case network
}

private let rgTranslateSessionConfiguration: URLSessionConfiguration = .ephemeral
private let rgTranslateSession: URLSession = URLSession(configuration: rgTranslateSessionConfiguration)

/// `translate.google.com/m` is an HTML page behind Google's bot protection and only answers to a
/// browser-shaped User-Agent. The JSON endpoints are happy with a plain mobile Safari one.
private let rgLegacyUserAgent: String = "Mozilla/4.0 (compatible;MSIE 6.0;Windows NT 5.1;SV1;.NET CLR 1.1.4322;.NET CLR 2.0.50727;.NET CLR 3.0.04506.30)"
private let rgUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"

/// Percent-encoding set for the `q=` parameter: RFC 3986 unreserved characters only, so that `+`,
/// `&` or `=` inside a message can not corrupt the query string.
private let rgTranslateQueryAllowedCharacters: CharacterSet = {
    var characterSet: CharacterSet = .alphanumerics
    characterSet.insert(charactersIn: "-._~")
    return characterSet
}()

/// Longest text sent in a single GET. Percent-encoded CJK costs up to 9 bytes per character, so
/// this keeps the request URL well inside what Google's frontend accepts.
private let rgTranslateMaxChunkLength: Int = 1200

// MARK: - Shared transport

private func rgTranslateRequestData(url: URL, userAgent: String) -> Signal<Data, TranslateFetchError> {
    return Signal { subscriber in
        let completed: Atomic<Bool> = Atomic(value: false)
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let downloadTask: URLSessionDataTask = rgTranslateSession.dataTask(with: request, completionHandler: { data, response, _ in
            let _ = completed.swap(true)
            guard let response: HTTPURLResponse = response as? HTTPURLResponse, response.statusCode == 200, let data: Data = data else {
                subscriber.putError(.network)
                return
            }
            subscriber.putNext(data)
            subscriber.putCompletion()
        })
        downloadTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadTask.cancel()
            }
        }
    }
}

private func rgTranslateEncode(_ text: String) -> String {
    return text.addingPercentEncoding(withAllowedCharacters: rgTranslateQueryAllowedCharacters) ?? ""
}

// MARK: - Chunking

/// Splits `text` into pieces no longer than `maxLength`, preferring line boundaries so that the
/// paragraph structure survives the round trip. A single line that is itself too long is split by
/// sentences.
private func rgTranslateSplitIntoChunks(_ text: String, maxLength: Int) -> [String] {
    if text.count <= maxLength {
        return [text]
    }

    var chunks: [String] = []
    var current: String?

    func flush() {
        if let value: String = current {
            chunks.append(value)
            current = nil
        }
    }

    for line in text.components(separatedBy: "\n") {
        if line.count > maxLength {
            flush()
            chunks.append(contentsOf: gtranslateSplitTextBySentences(line, maxChunkLength: maxLength))
            continue
        }
        if let value: String = current {
            if value.count + 1 + line.count <= maxLength {
                current = value + "\n" + line
            } else {
                flush()
                current = line
            }
        } else {
            current = line
        }
    }
    flush()

    return chunks.isEmpty ? [text] : chunks
}

private func rgTranslateInChunks(_ text: String, _ toLang: String, _ translateChunk: @escaping (String, String) -> Signal<String, TranslateFetchError>) -> Signal<String, TranslateFetchError> {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .single(text)
    }

    let chunks: [String] = rgTranslateSplitIntoChunks(text, maxLength: rgTranslateMaxChunkLength)
    if chunks.count == 1 {
        return translateChunk(chunks[0], toLang)
    }

    let signals: [Signal<String, TranslateFetchError>] = chunks.map { chunk in
        if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .single(chunk)
        }
        return translateChunk(chunk, toLang)
    }

    return combineLatest(signals)
    |> map { results in
        return results.joined(separator: "\n")
    }
}

// MARK: - translate.googleapis.com/translate_a/single

private func rgGoogleApiTranslateUrl(_ text: String, _ toLang: String) -> String {
    return "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(getGTranslateLang(toLang))&dt=t&ie=UTF-8&oe=UTF-8&q=\(rgTranslateEncode(text))"
}

/// `[[["translated","source",…],…],…]` — the translation is the concatenation of every block's
/// first element.
private func rgParseGoogleApiResponse(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], let blocks = json.first as? [Any] else {
        return nil
    }
    var result: String = ""
    for block in blocks {
        if let block = block as? [Any], let text = block.first as? String {
            result += text
        }
    }
    return result.isEmpty ? nil : result
}

private func rgGoogleApiTranslateChunk(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    guard let url: URL = URL(string: rgGoogleApiTranslateUrl(text, toLang)) else {
        return .fail(.network)
    }
    return rgTranslateRequestData(url: url, userAgent: rgUserAgent)
    |> mapToSignal { data -> Signal<String, TranslateFetchError> in
        guard let result: String = rgParseGoogleApiResponse(data) else {
            return .fail(.network)
        }
        return .single(result)
    }
}

// MARK: - clients5.google.com/translate_a/t

private func rgGoogleDictTranslateUrl(_ text: String, _ toLang: String) -> String {
    return "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=\(getGTranslateLang(toLang))&q=\(rgTranslateEncode(text))"
}

/// `[["translated","detected-source-language"]]` — a single element holding the whole translation.
private func rgParseGoogleDictResponse(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], let first = json.first else {
        return nil
    }
    let result: String?
    if let entry = first as? [Any] {
        result = entry.first as? String
    } else {
        result = first as? String
    }
    guard let result: String = result, !result.isEmpty else {
        return nil
    }
    return result
}

private func rgGoogleDictTranslateChunk(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    guard let url: URL = URL(string: rgGoogleDictTranslateUrl(text, toLang)) else {
        return .fail(.network)
    }
    return rgTranslateRequestData(url: url, userAgent: rgUserAgent)
    |> mapToSignal { data -> Signal<String, TranslateFetchError> in
        guard let result: String = rgParseGoogleDictResponse(data) else {
            return .fail(.network)
        }
        return .single(result)
    }
}

// MARK: - Legacy translate.google.com/m scraping

public func getTranslateUrl(_ message: String, _ toLang: String) -> String {
    let sanitizedMessage: String = message
    var queryCharSet: CharacterSet = .urlQueryAllowed
    queryCharSet.remove(charactersIn: "+&")
    return "https://translate.google.com/m?hl=en&tl=\(toLang)&sl=auto&q=\(sanitizedMessage.addingPercentEncoding(withAllowedCharacters: queryCharSet) ?? "")"
}

public func parseTranslateResponse(_ data: String) -> String {
    do {
        let document: Document = try SwiftSoup.parse(data)
        if let resultContainer: Element = try document.select("div.result-container").first() {
            return try resultContainer.text()
        } else if let tZero: Element = try document.select("div.t0").first() {
            return try tZero.text()
        }
    } catch {
    }
    return ""
}

public func requestTranslateUrl(url: URL) -> Signal<String, TranslateFetchError> {
    return rgTranslateRequestData(url: url, userAgent: rgLegacyUserAgent)
    |> mapToSignal { data -> Signal<String, TranslateFetchError> in
        guard let result: String = String(data: data, encoding: .utf8) else {
            return .fail(.network)
        }
        return .single(result)
    }
}

public func gtranslateSentence(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    guard let url: URL = URL(string: getTranslateUrl(text, getGTranslateLang(toLang))) else {
        return .fail(.network)
    }
    return requestTranslateUrl(url: url)
    |> mapToSignal { translatedHtml -> Signal<String, TranslateFetchError> in
        let result: String = parseTranslateResponse(translatedHtml)
        if result.isEmpty {
            return .fail(.network)
        }
        return .single(result)
    }
}

/// One request per line against the mobile web page. Kept as a last-resort fallback: Google answers
/// it with a 429 interstitial for most client IPs nowadays.
private func gtranslateViaMobilePage(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    let lines: [String] = text.components(separatedBy: "\n")

    let translationSignals: [Signal<String, TranslateFetchError>] = lines.map { rawLine in
        let leadingWhitespace: Substring = rawLine.prefix { $0.isWhitespace }
        let core: String = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if core.isEmpty {
            return .single(rawLine)
        }

        return gtranslateSentence(core, toLang)
        |> map { translatedCore in
            return String(leadingWhitespace) + translatedCore
        }
    }

    return combineLatest(translationSignals)
    |> map { results in
        let joined: String = results.joined(separator: "\n")
        return joined.isEmpty ? text : joined
    }
}

// MARK: - Public entry points

public func getGTranslateLang(_ userLang: String) -> String {
    var lang: String = userLang
    let rawSuffix: String = "-raw"
    if lang.hasSuffix(rawSuffix) {
        lang = String(lang.dropLast(rawSuffix.count))
    }
    lang = lang.lowercased()

    switch lang {
    case "zh-hans", "zh":
        return "zh-CN"
    case "zh-hant":
        return "zh-TW"
    case "he":
        return "iw"
    default:
        break
    }

    lang = lang.components(separatedBy: "-")[0].components(separatedBy: "_")[0]

    return lang
}

/// GTranslate backend: the `translate_a/single` JSON API, falling back to scraping the mobile web
/// page if it ever stops answering.
public func gtranslate(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    return rgTranslateInChunks(text, toLang, rgGoogleApiTranslateChunk)
    |> `catch` { _ -> Signal<String, TranslateFetchError> in
        return gtranslateViaMobilePage(text, toLang)
    }
}

/// Google backend: the `translate_a/t` JSON API used by Chrome's dictionary extension. It lives on
/// a different host with its own rate limiting, so it stays usable when the endpoint above is
/// throttled — which is why it is offered as a separate service rather than a silent fallback.
public func googleTranslate(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    return rgTranslateInChunks(text, toLang, rgGoogleDictTranslateChunk)
    |> `catch` { _ -> Signal<String, TranslateFetchError> in
        return rgTranslateInChunks(text, toLang, rgGoogleApiTranslateChunk)
    }
}

public func gtranslateSplitTextBySentences(_ text: String, maxChunkLength: Int = 1500) -> [String] {
    if text.count <= maxChunkLength {
        return [text]
    }
    var chunks: [String] = []
    var currentChunk: String = ""

    text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .bySentences) { substring, _, _, _ in
        guard let sentence: String = substring else {
            return
        }

        if currentChunk.count + sentence.count + 1 < maxChunkLength {
            currentChunk += sentence + " "
        } else {
            if !currentChunk.isEmpty {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            currentChunk = sentence + " "
        }
    }

    if !currentChunk.isEmpty {
        chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return chunks
}

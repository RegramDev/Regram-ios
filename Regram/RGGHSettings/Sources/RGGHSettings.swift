import Foundation
import RGLogging
import RGGHSettingsScheme
import AccountContext
import TelegramCore


public func updateRGGHSettingsInteractivelly(context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let _ = Task {
        do {
            let settings = try await fetchRGGHSettings(locale: locale)
            let _ = await (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.rgGHSettings = settings
                    return configuration
                })
            }).task()
        } catch {
            return
        }

    }
}


let maxRetries: Int = 3

enum RGGHFetchError: Error {
    case invalidURL
    case notFound
    case fetchFailed(statusCode: Int)
    case decodingFailed
}

func fetchRGGHSettings(locale: String) async throws -> RGGHSettings {
    let baseURL = "https://raw.githubusercontent.com/Swiftgram/settings/refs/heads/main"
    var candidates: [String] = []
    if let buildNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
        if locale != "en" {
            candidates.append("\(buildNumber)_\(locale).json")
        }
        candidates.append("\(buildNumber).json")
    }
    if locale != "en" {
        candidates.append("latest_\(locale).json")
    }
    candidates.append("latest.json")

    var lastError: Error?
    for candidate in candidates {
        let urlString = "\(baseURL)/\(candidate)"
        guard let url = URL(string: urlString) else {
            RGLogger.shared.log("SGGHSettings", "[0] Fetch failed for \(candidate). Invalid URL: \(urlString)")
            continue
        }

        attemptsOuter: for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else {
                    RGLogger.shared.log("SGGHSettings", "[\(attempt)] Fetch failed for \(candidate). Invalid response type: \(response)")
                    throw RGGHFetchError.fetchFailed(statusCode: -1)
                }

                switch httpResponse.statusCode {
                case 200:
                    do {
                        let jsonDecoder = JSONDecoder()
                        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
                        let settings = try jsonDecoder.decode(RGGHSettings.self, from: data)
                        RGLogger.shared.log("SGGHSettings", "[\(attempt)] Fetched \(candidate): \(settings)")
                        return settings
                    } catch {
                        RGLogger.shared.log("SGGHSettings", "[\(attempt)] Failed to decode \(candidate): \(error)")
                        throw RGGHFetchError.decodingFailed
                    }
                case 404:
                    RGLogger.shared.log("SGGHSettings", "[\(attempt)] Not found \(candidate) on the remote.")
                    break attemptsOuter
                default:
                    RGLogger.shared.log("SGGHSettings", "[\(attempt)] Fetch failed for \(candidate), status code: \(httpResponse.statusCode)")
                    throw RGGHFetchError.fetchFailed(statusCode: httpResponse.statusCode)
                }
            } catch {
                lastError = error
                if attempt == maxRetries {
                    break
                }
                try await Task.sleep(nanoseconds: UInt64(attempt * 2 * 1_000_000_000))
            }
        }
    }

    RGLogger.shared.log("SGGHSettings", "All attempts failed. Last error: \(String(describing: lastError))")
    throw RGGHFetchError.fetchFailed(statusCode: -1)
}

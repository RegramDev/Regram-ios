import Foundation

@main
struct URLTests {
    static func main() {
        let cases: [(String, String, String?)] = [
            ("", "", "https://api.openai.com/v1/chat/completions"),
            ("https://example.com", "/v1/chat/completions", "https://example.com/v1/chat/completions"),
            ("https://example.com/v1/", "/v1/chat/completions", "https://example.com/v1/chat/completions"),
            ("https://example.com/gateway/v1///", "v1/chat/completions", "https://example.com/gateway/v1/chat/completions"),
            ("https://example.com", "/v1/chat completions", "https://example.com/v1/chat%20completions"),
            ("https://example.com", "/接口/chat/completions", "https://example.com/%E6%8E%A5%E5%8F%A3/chat/completions"),
            ("https://example.com", "/v1/chat%completions", "https://example.com/v1/chat%25completions"),
            ("https://example.com", "/v1/chat%20completions", "https://example.com/v1/chat%20completions"),
            ("https://example.com/a%2Fb", "/v1/chat%2Fcompletions", "https://example.com/a%2Fb/v1/chat%2Fcompletions"),
            ("https://example.com", "/v1/chat/completions?api-version=2024-01-01", "https://example.com/v1/chat/completions?api-version=2024-01-01"),
            ("https://example.com/v1", "/v1/chat/completions?name=中文 空格&tag=%2B", "https://example.com/v1/chat/completions?name=%E4%B8%AD%E6%96%87%20%E7%A9%BA%E6%A0%BC&tag=%2B"),
            ("https://example.com?obsolete=true#base", "/v1/chat/completions?key=a%b#fragment", "https://example.com/v1/chat/completions?key=a%25b"),
            ("http://127.0.0.1:8080/gateway", "chat/completions", "http://127.0.0.1:8080/gateway/chat/completions"),
            ("http://[::1]:8080", "/v1/chat/completions", "http://[::1]:8080/v1/chat/completions"),
            ("invalid base", "https://other.example/v1/chat/completions?version=1", "https://other.example/v1/chat/completions?version=1"),
            ("https://example.com", "https://other.example/chat completions", "https://other.example/chat%20completions"),
            ("invalid base", "/v1/chat/completions", nil),
            ("file:///tmp/api", "/v1/chat/completions", nil),
            ("https://example.com", "ftp://other.example/api", nil),
            ("https://example.com", "//other.example/api", nil),
            ("https://example.com", "https:///api", nil),
            ("  https://example.com/v1/  ", "  /v1/chat/completions  ", "https://example.com/v1/chat/completions")
        ]
        for (base, endpoint, expected) in cases {
            let config = RGLLMTranslationConfiguration(format: .openai, baseURL: base, endpoint: endpoint, apiKey: "", model: "test", prompt: "", temperature: 0)
            precondition(config.translationURL?.absoluteString == expected, "URL mismatch: \(base) + \(endpoint): \(String(describing: config.translationURL))")
        }
        for format in RGLLMAPIFormat.allCases {
            let config = RGLLMTranslationConfiguration(format: format, baseURL: "https://example.com/gateway/v1/", endpoint: "", apiKey: "", model: "test", prompt: "", temperature: 0)
            precondition(config.modelsURL?.absoluteString == "https://example.com/gateway/v1/models")
            let expected = format == .openai ? "chat/completions" : "messages"
            precondition(config.translationURL?.absoluteString == "https://example.com/gateway/v1/\(expected)")
        }
        print("LLM production URL checks passed: \(cases.count + 4)")
    }
}

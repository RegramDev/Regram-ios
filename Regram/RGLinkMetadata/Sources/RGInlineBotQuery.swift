// MARK: Regram — automatic inline queries contain one pasted web link, never surrounding draft text.
import Foundation

public func rgInlineBotQueryText(_ text: String) -> String? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.utf8.count <= 2048,
          value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          let url = URLComponents(string: value),
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
        return nil
    }
    return value
}

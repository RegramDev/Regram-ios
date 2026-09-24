import Foundation

public func doesUrlMatchText(url: String, text: String, fullText: String) -> Bool {
    if fullText.range(of: "\u{202e}") != nil {
        return false
    }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    if !url.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
        return false
    }
    if url == text {
        return true
    }
    return false
}

public extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@"
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: generalDelimitersToEncode + subDelimitersToEncode)
        
        return allowed
    }()

    // MARK: Regram — every character RFC 3986 allows somewhere in a URL, `%` included so that
    // existing escapes survive.
    static let rgUrlAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
}

// MARK: Regram — before iOS 17 `URL(string:)` returns nil for any string holding a character RFC 3986
// forbids (CJK text, spaces, `|`...), where iOS 17+ percent-encodes such characters itself. This
// escapes only those, keeping every delimiter and existing escape, so an older system parses a link
// the way a newer one does instead of falling back to encoders that also escape `:`, `#` or `%`.
public func rgUrlEscapingIllegalCharacters(_ string: String) -> URL? {
    guard let escaped = string.addingPercentEncoding(withAllowedCharacters: .rgUrlAllowed) else {
        return nil
    }
    return URL(string: escaped)
}

public func isValidUrl(_ url: String, validSchemes: [String: Bool] = ["http": true, "https": true, "tonsite": true]) -> Bool {
    if let escapedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: escapedUrl), let scheme = url.scheme?.lowercased(), let requiresTopLevelDomain = validSchemes[scheme], let host = url.host, (!requiresTopLevelDomain || host.contains(".")) && url.user == nil {
        if requiresTopLevelDomain {
            let components = host.components(separatedBy: ".")
            let domain = (components.last ?? "")
            if domain.isEmpty {
                return false
            }
        }
        return true
    } else {
        return false
    }
}

public func explicitUrl(_ url: String) -> String {
    var url = url
    if !url.lowercased().hasPrefix("http:") && !url.lowercased().hasPrefix("https:") && !url.lowercased().hasPrefix("tonsite:") && url.range(of: "://") == nil {
        if let parsedUrl = URL(string: "http://\(url)"), parsedUrl.host?.hasSuffix(".ton") == true {
            url = "tonsite://\(url)"
        } else {
            url = "https://\(url)"
        }
    }
    return url
}

private let validUrlSet: CharacterSet = {
    var set = CharacterSet(charactersIn: "a".unicodeScalars.first! ... "z".unicodeScalars.first!)
    set.insert(charactersIn: "A".unicodeScalars.first! ... "Z".unicodeScalars.first!)
    set.insert(charactersIn: "0".unicodeScalars.first! ... "9".unicodeScalars.first!)
    set.insert(charactersIn: ".?!@#$^&%*-+=,:;'\"`<>()[]{}/\\|~ ")
    return set
}()

public func urlEncodedStringFromString(_ string: String) -> String {
    var nsString: NSString = string as NSString
    if let value = nsString.removingPercentEncoding {
        nsString = value as NSString
    }
    return nsString.addingPercentEncoding(withAllowedCharacters: validUrlSet) ?? ""
}

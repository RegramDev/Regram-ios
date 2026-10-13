// MARK: Regram — preview rules from the Nagram reference and its public metadata feed.
import RGSimpleSettings
import Foundation
import SwiftSignalKit
import TelegramCore

public struct RGPagePreviewRule: Codable, Equatable {
    public let regex: String
    public let replace: String
}

public struct RGPagePreviewDomain: Codable, Equatable {
    public let domain: String
    public let rules: [RGPagePreviewRule]
    public let regex: Bool?
}

public struct RGInlineBotRule: Codable, Equatable {
    public let username: String
    public let rules: [String]
}

private struct PagePreviewPayload: Codable {
    let domains: [RGPagePreviewDomain]
}

private struct InlineBotPayload: Codable {
    let data: [RGInlineBotRule]
}

/// Shared loader for the Android-compatible metadata published in
/// `@nagram_remote_metadata`. Cached rules remain usable offline.
public final class RGLinkMetadata {
    public static let shared = RGLinkMetadata()

    private static let channelName = "nagram_remote_metadata"
    private static let cacheKey = "rg.linkMetadata.cache.v1"
    private static let updateKey = "rg.linkMetadata.updatedAt.v1"
    private static let ttl: TimeInterval = 15.0 * 60.0

    private let lock = NSLock()
    private var pagePreviewDomains: [RGPagePreviewDomain]
    private var inlineRules: [RGInlineBotRule]
    private var refreshDisposable: MetaDisposable?

    private init() {
        let cached = Self.decodeMessages(UserDefaults.standard.stringArray(forKey: Self.cacheKey) ?? [])
        self.pagePreviewDomains = cached.pages.isEmpty ? Self.defaultPagePreviewDomains : cached.pages
        self.inlineRules = cached.inline.isEmpty ? Self.defaultInlineBotRules : cached.inline
    }

    public func previewUrl(_ value: String) -> String {
        let settings = RGSimpleSettings.shared
        guard settings.fixLinkPreviews else { return value }
        // Explicitly customized X/Instagram hosts take precedence over the reference/feed rules.
        let customHost = settings.linkPreviewXHost != RGLinkPreviewRules.defaultXHost || settings.linkPreviewInstagramHost != RGLinkPreviewRules.defaultInstagramHost
        if customHost {
            let qualified = value.contains("://") ? value : "https://" + value
            let host = URLComponents(string: qualified)?.host?.lowercased() ?? ""
            let hasOverride = (["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(host) && settings.linkPreviewXHost != RGLinkPreviewRules.defaultXHost)
                || (["instagram.com", "www.instagram.com"].contains(host) && settings.linkPreviewInstagramHost != RGLinkPreviewRules.defaultInstagramHost)
            if hasOverride { return RGLinkPreviewRules.repair(value) }
        }
        let parsedValue = value.range(of: "://") == nil ? "https://\(value)" : value
        guard var components = URLComponents(string: parsedValue), components.scheme?.lowercased() == "https", let host = components.host?.lowercased() else {
            return value
        }
        components.query = nil
        components.fragment = nil
        guard let sanitizedValue = components.string else {
            return value
        }
        self.lock.lock()
        let domains = self.pagePreviewDomains
        self.lock.unlock()
        guard let domain = domains.first(where: { item in
            return item.domain.lowercased() == host
        }) else {
            return RGLinkPreviewRules.repair(value)
        }
        var result = sanitizedValue
        for rule in domain.rules {
            guard let expression = try? NSRegularExpression(pattern: rule.regex) else { continue }
            result = expression.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: rule.replace)
        }
        guard result != sanitizedValue, let resultComponents = URLComponents(string: result), resultComponents.scheme?.lowercased() == "https", resultComponents.host != nil, resultComponents.user == nil, resultComponents.password == nil else {
            return value
        }
        return result
    }

    public func currentInlineBotRules() -> [RGInlineBotRule] {
        self.lock.lock()
        let result = self.inlineRules
        self.lock.unlock()
        return result
    }

    public func inlineBot(for text: String) -> RGInlineBotRule? {
        for item in self.currentInlineBotRules() {
            for pattern in item.rules {
                if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    return item
                }
            }
        }
        return nil
    }

    public func refreshIfNeeded(engine: TelegramEngine) {
        let updatedAt = UserDefaults.standard.double(forKey: Self.updateKey)
        guard Date().timeIntervalSince1970 - updatedAt >= Self.ttl else { return }
        self.lock.lock()
        guard self.refreshDisposable == nil else {
            self.lock.unlock()
            return
        }
        let holder = MetaDisposable()
        self.refreshDisposable = holder
        self.lock.unlock()

        let signal = engine.peers.resolvePeerByName(name: Self.channelName, referrer: nil, ageLimit: 60)
        |> mapToSignal { result -> Signal<EnginePeer.Id?, NoError> in
            guard case let .result(peer) = result else { return .complete() }
            return .single(peer?.id)
        }
        |> mapToSignal { peerId -> Signal<[String], NoError> in
            guard let peerId else { return .single([]) }
            return engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "#", state: nil, limit: 20)
            |> map { result, _ in result.messages.map(\.text) }
        }
        holder.set(signal.start(next: { [weak self] messages in
            guard let self, !messages.isEmpty else { return }
            let decoded = Self.decodeMessages(messages)
            guard !decoded.pages.isEmpty || !decoded.inline.isEmpty else { return }
            self.lock.lock()
            if !decoded.pages.isEmpty { self.pagePreviewDomains = decoded.pages }
            if !decoded.inline.isEmpty { self.inlineRules = decoded.inline }
            self.lock.unlock()
            UserDefaults.standard.set(messages, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.updateKey)
            DispatchQueue.main.async { NotificationCenter.default.post(name: RGLinkPreviewRules.didChangeNotification, object: nil) }
        }, completed: { [weak self] in
            self?.lock.lock()
            if self?.refreshDisposable === holder { self?.refreshDisposable = nil }
            self?.lock.unlock()
            holder.dispose()
        }))
    }

    private static func decodeMessages(_ messages: [String]) -> (pages: [RGPagePreviewDomain], inline: [RGInlineBotRule]) {
        var pages: [RGPagePreviewDomain] = []
        var inline: [RGInlineBotRule] = []
        let decoder = JSONDecoder()
        for message in messages {
            if message.hasPrefix("#pagepreview"), let data = String(message.dropFirst("#pagepreview".count)).data(using: .utf8), let payload = try? decoder.decode(PagePreviewPayload.self, from: data) {
                pages.append(contentsOf: payload.domains.filter(Self.isValidPagePreviewDomain))
            } else if message.hasPrefix("#inlinebot"), let data = String(message.dropFirst("#inlinebot".count)).data(using: .utf8), let payload = try? decoder.decode(InlineBotPayload.self, from: data) {
                inline.append(contentsOf: payload.data)
            }
        }
        return (pages, inline)
    }

    private static func isValidPagePreviewDomain(_ item: RGPagePreviewDomain) -> Bool {
        guard item.regex != true, !item.domain.isEmpty, item.domain.count <= 253, !item.rules.isEmpty, item.rules.count <= 8,
              let components = URLComponents(string: "https://\(item.domain)"), components.host?.lowercased() == item.domain.lowercased(), components.path.isEmpty else {
            return false
        }
        return item.rules.allSatisfy { rule in
            guard !rule.regex.isEmpty, rule.regex.count <= 512, rule.replace.count <= 512, !rule.replace.contains("\n"), !rule.replace.contains("\r") else {
                return false
            }
            return (try? NSRegularExpression(pattern: rule.regex)) != nil
        }
    }

    private static let defaultPagePreviewDomains: [RGPagePreviewDomain] = [
        .init(domain: "x.com", rules: [.init(regex: "x\\.com", replace: "fixupx.com")], regex: false),
        .init(domain: "twitter.com", rules: [.init(regex: "twitter\\.com", replace: "fxtwitter.com")], regex: false),
        .init(domain: "coolapk.com", rules: [.init(regex: "coolapk\\.com", replace: "coolapk1s.com")], regex: false),
        .init(domain: "www.coolapk.com", rules: [.init(regex: "coolapk\\.com", replace: "coolapk1s.com")], regex: false),
        .init(domain: "www.instagram.com", rules: [.init(regex: "www\\.instagram\\.com", replace: "ddinstagram.com")], regex: false),
        .init(domain: "vm.tiktok.com", rules: [.init(regex: "vm\\.tiktok\\.com", replace: "vm.vxtiktok.com")], regex: false),
        .init(domain: "www.reddit.com", rules: [.init(regex: "www\\.reddit\\.com", replace: "www.vxreddit.com")], regex: false),
        .init(domain: "bsky.app", rules: [.init(regex: "bsky\\.app", replace: "fxbsky.app")], regex: false),
        .init(domain: "www.pixiv.net", rules: [.init(regex: "www\\.pixiv\\.net", replace: "www.phixiv.net")], regex: false),
        .init(domain: "www.miyoushe.com", rules: [.init(regex: "www\\.miyoushe\\.com", replace: "www.miyoushe.pp.ua")], regex: false),
        .init(domain: "m.miyoushe.com", rules: [.init(regex: "m\\.miyoushe\\.com", replace: "www.miyoushe.pp.ua"), .init(regex: "(/#)|(\\?.*?/#)", replace: "")], regex: false),
        .init(domain: "www.hoyolab.com", rules: [.init(regex: "www\\.hoyolab\\.com", replace: "www.hoyolab.pp.ua")], regex: false),
        .init(domain: "m.moec.top", rules: [.init(regex: "m\\.moec\\.top/notes", replace: "t.me/iv?rhash=06c9960651c612&url=https://m.moec.top/notes")], regex: false),
        .init(domain: "sir.social", rules: [.init(regex: "sir\\.social", replace: "t.me/iv?rhash=f71a01ee06ddcd&url=https://sir.social")], regex: false),
    ]

    private static let defaultInlineBotRules: [RGInlineBotRule] = [
        .init(username: "twitter_loli_bot", rules: ["https?://(?:www\\.)?twitter\\.com/(\\w+/status/\\d+)", "https?://(?:www\\.)?x\\.com/(\\w+/status/\\d+)"]),
        .init(username: "Pixiv_bot", rules: ["https?://www\\.pixiv\\.net(?:/\\w+)?/artworks/\\S+"]),
        .init(username: "Music163bot", rules: ["https?://music\\.163\\.com/song\\?id=(\\d+)"]),
        .init(username: "autoivbot", rules: [
            "https?://www\\.ithome\\.com/\\S+", "https?://(?:.*?\\.)?v2ex\\.com/t/\\S+", "https?://www\\.nodeseek\\.com/\\S+", "https?://linux\\.do/t/topic/\\S+", "(?!\\S+\\.git)https?://github\\.com/[\\w-]+/[\\w.\\-]+(?:\\?\\S+)?$", "https?://(?:www\\.)?instagram\\.com/(p|reel)/([\\w-]+)/?", "https?://bsky\\.app/(profile/\\S+/post/\\S+)", "https?://(www\\.hoyolab|www\\.miyoushe)\\.com((?:/\\w+)?/article/\\d+)", "https?://m\\.(hoyolab|miyoushe)\\.com(/\\w+)?(?:\\?)?.*#(.*)"
        ]),
    ]
}

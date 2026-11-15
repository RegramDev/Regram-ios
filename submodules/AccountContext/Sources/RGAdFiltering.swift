// MARK: Regram — local display projection and explicit, account-scoped correction storage.
import Foundation
import Postbox
import TelegramCore
import RGSimpleSettings
import RGAdFilter

public func rgAdInput(_ message: Message) -> RGAdInput {
    let source = message.text as NSString
    let entities = (message.textEntitiesAttribute?.entities ?? []).compactMap { entity -> RGAdEntity? in
        let range = RGAdRange(entity.range.lowerBound, entity.range.upperBound)
        guard range.lower >= 0, range.upper <= source.length, range.upper > range.lower else { return nil }
        let kind: RGAdEntity.Kind
        let value: String?
        switch entity.type {
        case let .TextUrl(url): kind = .link; value = url
        case .Url: kind = .link; value = source.substring(with: range.nsRange)
        case .Mention: kind = .mention; value = source.substring(with: range.nsRange)
        case .TextMention: kind = .mention; value = nil
        case .Code, .Pre: kind = .code; value = nil
        case .BlockQuote: kind = .quote; value = nil
        case let .CustomEmoji(_, fileId): kind = .customEmoji; value = String(fileId)
        default: kind = .format; value = nil
        }
        return RGAdEntity(range: range, kind: kind, value: value)
    }
    let markup = message.attributes.first { $0 is ReplyMarkupMessageAttribute } as? ReplyMarkupMessageAttribute
    let buttons = (markup?.flags.contains(.inline) == true ? markup?.rows ?? [] : []).enumerated().map { row, value in
        value.buttons.enumerated().map { column, button -> RGAdButton in
            let target: String?
            switch button.action {
            case let .url(url), let .urlAuth(url, _), let .openWebView(url, _): target = url
            default: target = nil
            }
            return RGAdButton(id: "\(row):\(column)", title: button.title, target: target)
        }
    }
    let preview = message.media.compactMap { media -> String? in
        if let web = media as? TelegramMediaWebpage, case let .Loaded(content) = web.content { return content.url }
        return nil
    }.first
    return RGAdInput(text: message.text, peerId: message.id.peerId.toInt64(), entities: entities, buttons: buttons, hasMedia: message.media.contains { !($0 is TelegramMediaWebpage) }, previewTarget: preview)
}

public func rgCanCorrectAds(_ message: Message) -> Bool {
    message.id.namespace == Namespaces.Message.Cloud && message.id.peerId.namespace != Namespaces.Peer.SecretChat
        && !message.isCopyProtected() && !message.containsSecretMedia && message.richText == nil
        && (!message.text.isEmpty || !message.media.isEmpty || message.attributes.contains { $0 is ReplyMarkupMessageAttribute })
}

// MARK: Regram — cloud groups and broadcast channels share the same incoming-ad policy.
private func rgIsAdFilteringPeer(_ message: Message) -> Bool {
    let peer = message.peers[message.id.peerId]
    return peer is TelegramChannel || peer is TelegramGroup
}

// MARK: Regram — snapshots use the same media identity in automatic and manual collection.
public func rgAdSampleDraft(_ message: Message, store: RGAdSampleStore) throws -> RGAdSample {
    try store.draft(input: rgAdInput(message), messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: rgAdMediaIdentity(message))
}
private func rgAdSampleKey(_ message: Message) -> String { "\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)" }
private func rgAdMediaIdentity(_ message: Message) -> String { message.media.map { String(describing: $0.id) }.joined(separator: ":") }
private func rgAdMediaKinds(_ message: Message) -> [String] {
    message.media.filter { !($0 is TelegramMediaWebpage) }.map { media in
        if media is TelegramMediaImage { return "image" }
        if let file = media as? TelegramMediaFile { return file.isVideo ? "video" : file.isVoice ? "voice" : "file" }
        return "other"
    }
}

private final class RGAdOriginalAttribute: MessageAttribute {
    let source: Message?
    let removedRanges: [RGAdRange]
    let bodyLength: Int
    init(_ source: Message, projection: RGAdProjection) { self.source = source; removedRanges = projection.removedRanges; bodyLength = projection.text.utf16.count }
    required init(decoder: PostboxDecoder) { source = nil; removedRanges = []; bodyLength = 0 }
    func encode(_ encoder: PostboxEncoder) {} // Display-only; never encode the original message.
}

public func rgAdOriginalMessage(_ message: Message) -> Message {
    (message.attributes.first { $0 is RGAdOriginalAttribute } as? RGAdOriginalAttribute)?.source ?? message
}

public func rgAdMessageWasFiltered(_ message: Message) -> Bool { message.attributes.contains { $0 is RGAdOriginalAttribute } }

/// Quote offsets refer to the server's original text. A selection spanning a removed interval
/// cannot be a contiguous server quote and must fall back to a plain reply.
public func rgAdOriginalRange(_ message: Message, range: NSRange) -> NSRange? {
    guard let attribute = message.attributes.first(where: { $0 is RGAdOriginalAttribute }) as? RGAdOriginalAttribute else { return range }
    guard let source = attribute.source, range.location >= 0, range.length > 0, range.location <= attribute.bodyLength,
          range.length <= attribute.bodyLength - range.location else { return nil }
    var originalStart = 0, displayStart = 0
    for cut in attribute.removedRanges + [RGAdRange(source.text.utf16.count, source.text.utf16.count)] {
        let length = cut.lower - originalStart
        if range.location >= displayStart, NSMaxRange(range) <= displayStart + length {
            return NSRange(location: originalStart + range.location - displayStart, length: range.length)
        }
        originalStart = cut.upper; displayStart += length
    }
    return nil
}

/// Expensive matching and file access run off the rendering thread. UI reads only prepared values.
public final class RGAdFilterSession {
    public enum Scope: Hashable { case history, pinned, chatList(UUID) }
    private static let registryLock = NSLock()
    private static var sessions: [String: RGAdFilterSession] = [:]
    public static func get(_ context: AccountContext) -> RGAdFilterSession {
        registryLock.lock(); defer { registryLock.unlock() }
        let path = context.account.basePath
        if let session = sessions[path] { return session }
        let session = RGAdFilterSession(path: path)
        sessions[path] = session
        return session
    }

    private let queue = DispatchQueue(label: "regram.ad-filter", qos: .userInitiated)
    private let lock = NSLock()
    private let store: RGAdSampleStore
    private var knowledge = RGAdPolicy.Knowledge()
    private var lastBatches: [Scope: [MessageId: RGAdInput]] = [:]
    private var lastMedia: [Scope: [MessageId: String]] = [:]
    private var requestedVersions: [Scope: [MessageId: UInt32]] = [:]
    private var requestGenerations: [Scope: UInt64] = [:]
    private var salt = ""
    private var enabled = false
    private struct Cached { let input: RGAdInput; let mediaIdentity: String; let projection: RGAdProjection?; let revision: UInt32; let preservesMedia: Bool }
    private var revision: UInt32 = 0
    // MARK: Regram — scrolling must not evict the currently displayed pinned result.
    private var cached: [Scope: [MessageId: Cached]] = [:]
    private var order: [Scope: [MessageId]] = [:]
    private init(path: String) {
        store = RGAdSampleStore(accountDirectory: URL(fileURLWithPath: path))
        queue.async { [weak self] in
            guard let self else { return }
            try? self.reload()
            self.changed()
        }
    }

    private func reload() throws {
        let samples = try store.load(), salt = try store.salt(), enabled = try store.isEnabled()
        self.knowledge = RGAdPolicy.Knowledge(samples: samples); self.salt = salt; self.enabled = enabled; self.lastBatches = [:]; self.lastMedia = [:]
        lock.lock(); cached.removeAll(); order.removeAll(); lock.unlock()
    }
    private func changed() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil) }
    }

    public func perform<T>(changes: Bool = false, _ work: @escaping (RGAdSampleStore) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        queue.async {
            let result: Result<T, Error>
            do {
                let value = try work(self.store)
                if changes { try self.reload(); self.changed() }
                result = .success(value)
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // Completion is delivered on the classifier queue, including coalesced/no-change requests.
    // Preview consumers can render the final result without relying on a notification race.
    public func prepare(_ messages: [Message], accountPeerId: PeerId, scope: Scope = .history, completion: (() -> Void)? = nil) {
        var versions: [MessageId: UInt32] = [:]
        for message in messages { versions[message.id] = message.stableVersion }
        lock.lock()
        if requestedVersions[scope] != versions {
            requestedVersions[scope] = versions
            requestGenerations[scope] = (requestGenerations[scope] ?? 0) &+ 1
        }
        let request = requestGenerations[scope] ?? 0
        lock.unlock()
        queue.async {
            defer { completion?() }
            self.lock.lock(); let latest = request == (self.requestGenerations[scope] ?? 0); self.lock.unlock()
            guard latest else { return } // Coalesce stale scroll windows before doing any matching.
            let capacity: Int
            switch scope { case .history: capacity = 512; case .pinned: capacity = 64; case .chatList: capacity = 8192 }
            let eligible = Array(messages.filter { message in
                guard rgCanCorrectAds(message), message.effectivelyIncoming(accountPeerId), rgIsAdFilteringPeer(message) else { return false }
                return message.adAttribute == nil && message.activeEphemeralReplacementMessage == nil
            }.suffix(capacity).reversed())
            var inputs: [MessageId: RGAdInput] = [:]
            var identities: [MessageId: String] = [:]
            for message in eligible { inputs[message.id] = rgAdInput(message); identities[message.id] = rgAdMediaIdentity(message) }
            // In particular, a window larger than the bounded cache must not trigger a refresh loop.
            guard inputs != self.lastBatches[scope] || identities != self.lastMedia[scope] else { return }
            let previousHidden = self.hiddenMessageIds(in: eligible, accountPeerId: accountPeerId, scope: scope)
            var changed = false
            var completed = true
            var lastRefresh = ProcessInfo.processInfo.systemUptime
            for message in eligible {
                self.lock.lock(); let current = request == (self.requestGenerations[scope] ?? 0); self.lock.unlock()
                if !current { completed = false; break }
                guard let input = inputs[message.id] else { continue }
                self.lock.lock(); let old = self.cached[scope]?[message.id]; self.lock.unlock()
                let mediaIdentity = identities[message.id] ?? ""
                if old?.input == input && old?.mediaIdentity == mediaIdentity { continue }
                let group = RGAdSampleStore.sourceGroup(salt: self.salt, peerId: message.id.peerId.toInt64())
                let sampleId = try? RGAdSampleStore.sampleId(input: input, salt: self.salt, messageKey: rgAdSampleKey(message), mediaIdentity: mediaIdentity)
                let semantic = self.enabled ? RGAdSemanticClassifier.shared.predict(input) : RGAdSemanticResult()
                let result = self.enabled ? try? self.knowledge.project(input, sourceGroup: group, semantic: semantic, sampleId: sampleId) : nil
                let projected = result?.disposition == .keep ? nil : result
                // MARK: Regram — local pending records are never fed back into the classifier.
                // Recording failures must not block display; the settings library exposes them.
                if let projected {
                    try? self.store.recordDetection(input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: rgAdMediaIdentity(message), projection: projected)
                }
                self.lock.lock()
                if self.cached[scope]?[message.id] == nil {
                    if self.order[scope, default: []].count >= capacity {
                        let evicted = self.order[scope]!.removeFirst()
                        self.cached[scope]?.removeValue(forKey: evicted)
                    }
                    self.order[scope, default: []].append(message.id)
                }
                self.revision &+= 1
                self.cached[scope, default: [:]][message.id] = Cached(input: input, mediaIdentity: mediaIdentity, projection: projected, revision: self.revision, preservesMedia: self.knowledge.preservesMedia(input, sourceGroup: group, sampleId: sampleId))
                self.lock.unlock()
                changed = changed || projected != nil || old?.projection != nil
                if changed && ProcessInfo.processInfo.systemUptime - lastRefresh >= 0.25 {
                    self.changed(); changed = false; lastRefresh = ProcessInfo.processInfo.systemUptime
                }
            }
            if completed {
                self.lastBatches[scope] = inputs
                self.lastMedia[scope] = identities
                // Album-only pictures share their caption's verdict, but remain separate pending
                // records, so the user can correct an attachment without relabelling its caption.
                let hidden = self.hiddenMessageIds(in: eligible, accountPeerId: accountPeerId, scope: scope)
                changed = changed || hidden != previousHidden
                for message in eligible where hidden.contains(message.id) && !self.shouldHide(message, accountPeerId: accountPeerId, scope: scope) {
                    if let input = inputs[message.id] {
                        let projection = RGAdProjection(disposition: .hide, text: "", entities: [], buttons: [], removedRanges: [], removedButtonIds: [], hideLinkPreview: true)
                        try? self.store.recordDetection(input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: rgAdMediaIdentity(message), projection: projection)
                    }
                }
            }
            if changed { self.changed() }
        }
    }

    public func release(scope: Scope) {
        queue.async {
            self.lastBatches.removeValue(forKey: scope)
            self.lastMedia.removeValue(forKey: scope)
            self.lock.lock()
            self.cached.removeValue(forKey: scope); self.order.removeValue(forKey: scope)
            self.requestedVersions.removeValue(forKey: scope); self.requestGenerations.removeValue(forKey: scope)
            self.lock.unlock()
        }
    }

    private func prepared(_ message: Message, scope: Scope?) -> Cached? {
        lock.lock()
        let candidates = scope.map { [cached[$0]?[message.id], cached[.history]?[message.id], cached[.pinned]?[message.id]] }
            ?? [cached[.history]?[message.id], cached[.pinned]?[message.id]]
        lock.unlock()
        let input = rgAdInput(message)
        let mediaIdentity = rgAdMediaIdentity(message)
        return candidates.compactMap { $0 }.first { $0.input == input && $0.mediaIdentity == mediaIdentity }
    }

    private func canProject(_ message: Message, accountPeerId: PeerId) -> Bool {
        guard rgCanCorrectAds(message), message.effectivelyIncoming(accountPeerId), rgIsAdFilteringPeer(message),
              message.adAttribute == nil, message.activeEphemeralReplacementMessage == nil else { return false }
        // MARK: Regram — keyword rules hide whole messages and have their own legacy opt-outs.
        // They must not silently disable the independent, account-scoped segment cleaner.
        let settings = RGSimpleSettings.shared
        guard settings.chatPreferences(accountId: accountPeerId.toInt64(), peerId: message.id.peerId.toInt64()).adFiltering != false,
              !settings.temporarilyVisiblePeerIds(accountId: accountPeerId.toInt64()).contains(message.id.peerId.toInt64()) else { return false }
        return true
    }

    private func projection(_ message: Message, accountPeerId: PeerId, scope: Scope?) -> Cached? {
        guard canProject(message, accountPeerId: accountPeerId) else { return nil }
        return prepared(message, scope: scope)
    }

    public func shouldHide(_ message: Message, accountPeerId: PeerId, scope: Scope? = nil) -> Bool {
        projection(message, accountPeerId: accountPeerId, scope: scope)?.projection?.disposition == .hide
    }

    // MARK: Regram — a preview fallback must not expose an older unclassified advertisement.
    public func isPrepared(_ message: Message, accountPeerId: PeerId, scope: Scope? = nil) -> Bool {
        !canProject(message, accountPeerId: accountPeerId) || prepared(message, scope: scope) != nil
    }

    /// Captionless members inherit only a complete ad verdict within the same Telegram album.
    /// A separate neighbouring picture, surviving caption/button, or reviewed media is preserved.
    public func hiddenMessageIds(in messages: [Message], accountPeerId: PeerId, scope: Scope? = nil) -> Set<MessageId> {
        struct Album: Hashable { let peerId: PeerId; let namespace: Int32; let key: Int64 }
        var hidden = Set(messages.filter { shouldHide($0, accountPeerId: accountPeerId, scope: scope) }.map(\.id))
        var albums: [Album: [Message]] = [:]
        for message in messages {
            if let key = message.groupingKey { albums[Album(peerId: message.id.peerId, namespace: message.id.namespace, key: key), default: []].append(message) }
        }
        for members in albums.values {
            let captions = members.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.attributes.contains { $0 is ReplyMarkupMessageAttribute } }
            guard !captions.isEmpty, captions.allSatisfy({ hidden.contains($0.id) }),
                  members.allSatisfy({ canProject($0, accountPeerId: accountPeerId) && prepared($0, scope: scope)?.preservesMedia == false }) else { continue }
            for message in members where rgAdInput(message).hasMedia { hidden.insert(message.id) }
        }
        return hidden
    }

    public func display(_ message: Message, accountPeerId: PeerId, scope: Scope? = nil) -> Message {
        guard let value = projection(message, accountPeerId: accountPeerId, scope: scope), let projection = value.projection else { return message }
        let removed = projection.removedRanges
        func mapped(_ range: Range<Int>) -> [Range<Int>] {
            var result: [Range<Int>] = [], offset = 0, start = 0
            for cut in removed + [RGAdRange(message.text.utf16.count, message.text.utf16.count)] {
                let lower = max(start, range.lowerBound), upper = min(cut.lower, range.upperBound)
                if lower < upper { result.append((lower - offset)..<(upper - offset)) }
                offset += cut.upper - cut.lower; start = cut.upper
            }
            return result
        }
        var attributes: [MessageAttribute] = []
        for attribute in message.attributes {
            if let entities = attribute as? TextEntitiesMessageAttribute {
                attributes.append(TextEntitiesMessageAttribute(entities: entities.entities.flatMap { entity in mapped(entity.range).map { MessageTextEntity(range: $0, type: entity.type) } }))
            } else if let markup = attribute as? ReplyMarkupMessageAttribute, markup.flags.contains(.inline) {
                let ids = Set(projection.removedButtonIds)
                let rows = markup.rows.enumerated().compactMap { row, item -> ReplyMarkupRow? in
                    let buttons = item.buttons.enumerated().compactMap { column, button in ids.contains("\(row):\(column)") ? nil : button }
                    return buttons.isEmpty ? nil : ReplyMarkupRow(buttons: buttons)
                }
                if !rows.isEmpty { attributes.append(ReplyMarkupMessageAttribute(rows: rows, flags: markup.flags, placeholder: markup.placeholder)) }
            } else if !(attribute is TranslationMessageAttribute) { attributes.append(attribute) }
        }
        attributes.append(RGAdOriginalAttribute(message, projection: projection))
        // History/bubble diffing keys off stableVersion, even when text/attributes changed. This
        // display-only token refreshes corrections without altering the stored source version.
        var result = message.withUpdatedText(projection.text).withUpdatedAttributes(attributes).withUpdatedStableVersion(stableVersion: message.stableVersion &+ 0x8000_0000 &+ value.revision)
        if projection.hideLinkPreview { result = result.withUpdatedMedia(message.media.filter { !($0 is TelegramMediaWebpage) }) }
        return result
    }
}

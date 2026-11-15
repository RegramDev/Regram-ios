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

private final class RGAdOriginalAttribute: MessageAttribute {
    let source: Message?
    init(_ source: Message) { self.source = source }
    required init(decoder: PostboxDecoder) { source = nil }
    func encode(_ encoder: PostboxEncoder) {} // Display-only; never encode the original message.
}

public func rgAdOriginalMessage(_ message: Message) -> Message {
    (message.attributes.first { $0 is RGAdOriginalAttribute } as? RGAdOriginalAttribute)?.source ?? message
}

public func rgAdMessageWasFiltered(_ message: Message) -> Bool { message.attributes.contains { $0 is RGAdOriginalAttribute } }

/// Expensive matching and file access run off the rendering thread. UI reads only prepared values.
public final class RGAdFilterSession {
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
    private var lastBatch: [MessageId: RGAdInput] = [:]
    private var requestGeneration: UInt64 = 0
    private var salt = ""
    private var enabled = false
    private struct Cached { let input: RGAdInput; let projection: RGAdProjection?; let revision: UInt32 }
    private var revision: UInt32 = 0
    private var cached: [MessageId: Cached] = [:]
    private var order: [MessageId] = []
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
        self.knowledge = RGAdPolicy.Knowledge(samples: samples); self.salt = salt; self.enabled = enabled; self.lastBatch = [:]
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

    public func prepare(_ messages: [Message], accountPeerId: PeerId) {
        lock.lock(); requestGeneration &+= 1; let request = requestGeneration; lock.unlock()
        queue.async {
            self.lock.lock(); let latest = request == self.requestGeneration; self.lock.unlock()
            guard latest else { return } // Coalesce stale scroll windows before doing any matching.
            let eligible = messages.filter { message in
                guard rgCanCorrectAds(message), message.effectivelyIncoming(accountPeerId),
                      let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info else { return false }
                return message.adAttribute == nil && message.activeEphemeralReplacementMessage == nil
            }
            var inputs: [MessageId: RGAdInput] = [:]
            for message in eligible { inputs[message.id] = rgAdInput(message) }
            // In particular, a window larger than the bounded cache must not trigger a refresh loop.
            guard inputs != self.lastBatch else { return }
            self.lastBatch = inputs
            var changed = false
            for message in eligible {
                guard let input = inputs[message.id] else { continue }
                self.lock.lock(); let old = self.cached[message.id]; self.lock.unlock()
                if old?.input == input { continue }
                let group = RGAdSampleStore.sourceGroup(salt: self.salt, peerId: message.id.peerId.toInt64())
                let result = self.enabled ? try? self.knowledge.project(input, sourceGroup: group) : nil
                let projected = result?.disposition == .keep ? nil : result
                self.lock.lock()
                if self.cached[message.id] == nil {
                    if self.order.count >= 512 { self.cached.removeValue(forKey: self.order.removeFirst()) }
                    self.order.append(message.id)
                }
                self.revision &+= 1
                self.cached[message.id] = Cached(input: input, projection: projected, revision: self.revision)
                self.lock.unlock()
                changed = changed || projected != nil || old?.projection != nil
            }
            if changed { self.changed() }
        }
    }

    public func display(_ message: Message, accountPeerId: PeerId, notice: String) -> Message {
        guard rgCanCorrectAds(message), message.effectivelyIncoming(accountPeerId),
              let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info,
              message.adAttribute == nil, message.activeEphemeralReplacementMessage == nil else { return message }
        // Respect the existing per-chat disable/temporary reveal controls.
        let settings = RGSimpleSettings.shared
        guard !settings.messageFilterDisabledPeerIds.contains(message.id.peerId.toInt64()),
              !settings.temporarilyVisiblePeerIds(accountId: accountPeerId.toInt64()).contains(message.id.peerId.toInt64()) else { return message }
        lock.lock(); let value = cached[message.id]; lock.unlock()
        guard let value, let projection = value.projection, value.input == rgAdInput(message) else { return message }
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
        attributes.append(RGAdOriginalAttribute(message))
        // A small placeholder keeps the original reachable even for a wholly promotional message.
        let body = projection.text + (projection.text.isEmpty ? "" : "\n\n") + notice
        // History/bubble diffing keys off stableVersion, even when text/attributes changed. This
        // display-only token refreshes corrections without altering the stored source version.
        var result = message.withUpdatedText(body).withUpdatedAttributes(attributes).withUpdatedStableVersion(stableVersion: message.stableVersion &+ 0x8000_0000 &+ value.revision)
        if projection.hideLinkPreview { result = result.withUpdatedMedia(message.media.filter { !($0 is TelegramMediaWebpage) }) }
        return result
    }
}

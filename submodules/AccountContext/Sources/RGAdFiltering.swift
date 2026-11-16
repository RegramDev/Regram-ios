// MARK: Regram — local display projection and explicit, account-scoped correction storage.
import Foundation
#if canImport(UIKit)
import UIKit
#endif
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
    public enum Scope: Hashable { case history, pinned, historyView(UUID), pinnedView(UUID), chatList(UUID) }
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

    private let queue = DispatchQueue(label: "regram.ad-filter", qos: .utility)
    private let lock = NSLock()
    private let store: RGAdSampleStore
    private var knowledge = RGAdPolicy.Knowledge()
    private var lastBatches: [Scope: [MessageId: RGAdInput]] = [:]
    private var lastMedia: [Scope: [MessageId: String]] = [:]
    private var requestedVersions: [Scope: [MessageId: UInt32]] = [:]
    private var requestGenerations: [Scope: UInt64] = [:]
    private var salt = ""
    private var enabled = false
    private final class Cached {
        let input: RGAdInput; let mediaIdentity: String; let projection: RGAdProjection?; let revision: UInt32; let preservesMedia: Bool; let completed: Bool
        // Weak identity memoization avoids re-extracting entities on every bubble/preview read.
        // The original Message is never retained by the filter cache.
        weak var validatedSource: Message?
        init(input: RGAdInput, mediaIdentity: String, projection: RGAdProjection?, revision: UInt32, preservesMedia: Bool, source: Message, completed: Bool) {
            self.input = input; self.mediaIdentity = mediaIdentity; self.projection = projection; self.revision = revision
            self.preservesMedia = preservesMedia; self.validatedSource = source
            self.completed = completed
        }
    }
    private final class Batch {
        let scope: Scope; let generation: UInt64; let messages: [Message]; let account: PeerId
        let inputs: [MessageId: RGAdInput]; let identities: [MessageId: String]; let previousHidden: Set<MessageId>
        var cursor = 0
        var incomplete = false
        var requests: [(RGAdWorkRequest, (() -> Void)?)] = []
        init(scope: Scope, generation: UInt64, messages: [Message], account: PeerId, inputs: [MessageId: RGAdInput], identities: [MessageId: String], previousHidden: Set<MessageId>) {
            self.scope = scope; self.generation = generation; self.messages = messages; self.account = account
            self.inputs = inputs; self.identities = identities; self.previousHidden = previousHidden
        }
    }
    private lazy var scheduler = RGAdWorkScheduler(queue: queue)
    private var pending: [Scope: Batch] = [:]
    private var sourceGroups: [PeerId: String] = [:]
    private var sharedCache: [MessageId: Cached] = [:]
    private var sharedOrder: [MessageId] = []
    private var cacheEpoch: UInt64 = 0
    private var refreshScheduled = false
    private var retryNeeded = false
    private var retryScheduled = false
    private var foreground = true
    private var observers: [NSObjectProtocol] = []
    private var revision: UInt32 = 0
    // MARK: Regram — scrolling must not evict the currently displayed pinned result.
    private var cached: [Scope: [MessageId: Cached]] = [:]
    private var order: [Scope: [MessageId]] = [:]
    private init(path: String) {
        store = RGAdSampleStore(accountDirectory: URL(fileURLWithPath: path))
        queue.async { [weak self] in
            guard let self else { return }
            try? self.reload()
            self.updateWorkConditions()
            self.changed()
        }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in self?.updateWorkConditions() }
            })
        }
        #if canImport(UIKit)
        for (name, active) in [(UIApplication.didEnterBackgroundNotification, false), (UIApplication.willEnterForegroundNotification, true)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in self?.foreground = active; self?.updateWorkConditions() }
            })
        }
        DispatchQueue.main.async { [weak self] in
            let active = UIApplication.shared.applicationState != .background
            self?.queue.async { [weak self] in self?.foreground = active; self?.updateWorkConditions() }
        }
        #endif
    }

    private func updateWorkConditions() {
        let conditions = RGAdWorkConditions(foreground: foreground, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: ProcessInfo.processInfo.thermalState.rawValue)
        scheduler.updateConditions(conditions)
        if !conditions.paused { scheduleRetry() }
    }

    private func scheduleRetry() {
        guard retryNeeded, !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 60) {
            self.retryScheduled = false
            guard self.retryNeeded, self.foreground, ProcessInfo.processInfo.thermalState.rawValue < 3 else { return }
            self.retryNeeded = false
            self.changed()
        }
    }

    private func reload() throws {
        let samples = try store.load(), salt = try store.salt(), enabled = try store.isEnabled()
        self.knowledge = RGAdPolicy.Knowledge(samples: samples); self.salt = salt; self.enabled = enabled; self.lastBatches = [:]; self.lastMedia = [:]
        sourceGroups.removeAll()
        pending.removeAll()
        retryNeeded = false
        lock.lock()
        cacheEpoch &+= 1
        cached.removeAll(); order.removeAll(); sharedCache.removeAll(); sharedOrder.removeAll()
        lock.unlock()
    }
    private func changed() {
        // One notification per second for all scopes; a completed preview also receives its
        // result directly. Rendering must not restart every 250 ms while a long batch runs.
        guard !refreshScheduled else { return }
        refreshScheduled = true
        queue.asyncAfter(deadline: .now() + 1) {
            self.refreshScheduled = false
            DispatchQueue.main.async { NotificationCenter.default.post(name: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil) }
        }
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

    private func isCurrent(_ scope: Scope, generation: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return requestGenerations[scope] == generation
    }

    // Completion is delivered off the UI thread. Cancelling a consumer stops unused work, too.
    @discardableResult public func prepare(_ messages: [Message], accountPeerId: PeerId, scope: Scope = .history, completion: (() -> Void)? = nil) -> RGAdWorkRequest {
        let token = RGAdWorkRequest()
        var versions: [MessageId: UInt32] = [:]
        for message in messages { versions[message.id] = message.stableVersion }
        lock.lock()
        if requestedVersions[scope] != versions {
            requestedVersions[scope] = versions
            requestGenerations[scope] = (requestGenerations[scope] ?? 0) &+ 1
        }
        let generation = requestGenerations[scope] ?? 0
        lock.unlock()
        queue.async {
            guard !token.isCancelled else { return }
            guard self.isCurrent(scope, generation: generation) else { completion?(); return }
            let capacity = self.capacity(scope)
            // Explicit opt-outs and temporary original-message mode must not consume model work.
            let eligible = self.enabled ? Array(messages.filter { self.canProject($0, accountPeerId: accountPeerId) }.suffix(capacity).reversed()) : []
            var inputs: [MessageId: RGAdInput] = [:], identities: [MessageId: String] = [:]
            for message in eligible { inputs[message.id] = rgAdInput(message); identities[message.id] = rgAdMediaIdentity(message) }
            if let batch = self.pending[scope], batch.generation == generation, batch.inputs == inputs, batch.identities == identities {
                batch.requests.append((token, completion)); return
            }
            guard inputs != self.lastBatches[scope] || identities != self.lastMedia[scope] else { completion?(); return }
            let batch = Batch(scope: scope, generation: generation, messages: eligible, account: accountPeerId, inputs: inputs, identities: identities,
                              previousHidden: self.hiddenMessageIds(in: eligible, accountPeerId: accountPeerId, scope: scope))
            batch.requests.append((token, completion)); self.pending[scope] = batch
            self.scheduler.enqueue(cancelled: {
                self.pending[scope] !== batch || !self.isCurrent(scope, generation: generation) || batch.requests.allSatisfy { $0.0.isCancelled }
            }, step: {
                if batch.cursor < batch.messages.count {
                    self.process(batch.messages[batch.cursor], batch: batch); batch.cursor += 1
                }
                if batch.cursor == batch.messages.count { self.finish(batch, completed: true); return true }
                return false
            }, onCancel: { self.finish(batch, completed: false) })
        }
        return token
    }

    private func capacity(_ scope: Scope) -> Int {
        switch scope { case .history, .historyView: return 512; case .pinned, .pinnedView: return 64; case .chatList: return 8192 }
    }

    private func process(_ message: Message, batch: Batch) {
        let scope = batch.scope
        guard let input = batch.inputs[message.id] else { return }
        let mediaIdentity = batch.identities[message.id] ?? ""
        lock.lock()
        let old = cached[scope]?[message.id]
        let reuse = [old, sharedCache[message.id]].compactMap { $0 }.first { $0.completed && $0.input == input && $0.mediaIdentity == mediaIdentity }
        lock.unlock()
        let value: Cached
        if let reuse { value = reuse }
        else {
            let group: String
            if let existing = sourceGroups[message.id.peerId] { group = existing }
            else { group = RGAdSampleStore.sourceGroup(salt: salt, peerId: message.id.peerId.toInt64()); sourceGroups[message.id.peerId] = group }
            let sampleId = try? RGAdSampleStore.sampleId(input: input, salt: salt, messageKey: rgAdSampleKey(message), mediaIdentity: mediaIdentity)
            var completed = true
            let result: RGAdProjection?
            do {
                result = try knowledge.resolve(input, sourceGroup: group, sampleId: sampleId) { input in
                    let semantic = RGAdSemanticClassifier.shared.predict(input)
                    completed = semantic.completed
                    return semantic
                }
            } catch RGAdFilterError.budgetExceeded { completed = false; result = nil }
            catch { result = nil }
            let projected = result?.disposition == .keep ? nil : result
            if !completed {
                batch.incomplete = true; retryNeeded = true; scheduleRetry()
                // Keep already confirmed cuts visible, but never cache a failed inference as
                // normal. Identical partial results must not create a notification/retry loop.
                guard projected != nil else { return }
                if let old, old.input == input, old.mediaIdentity == mediaIdentity, old.projection == projected { return }
            }
            if let projected {
                try? store.recordDetection(input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: mediaIdentity, projection: projected)
            }
            revision &+= 1
            value = Cached(input: input, mediaIdentity: mediaIdentity, projection: projected, revision: revision,
                           preservesMedia: knowledge.preservesMedia(input, sourceGroup: group, sampleId: sampleId), source: message, completed: completed)
        }
        lock.lock()
        if cached[scope]?[message.id] == nil {
            if order[scope, default: []].count >= capacity(scope), let evicted = order[scope]?.removeFirst() { cached[scope]?.removeValue(forKey: evicted) }
            order[scope, default: []].append(message.id)
        }
        cached[scope, default: [:]][message.id] = value
        if sharedCache[message.id] == nil {
            if sharedOrder.count >= 8192 { sharedCache.removeValue(forKey: sharedOrder.removeFirst()) }
            sharedOrder.append(message.id)
        }
        sharedCache[message.id] = value
        lock.unlock()
        if old !== value && (old?.projection != nil || value.projection != nil) { changed() }
    }

    private func finish(_ batch: Batch, completed: Bool) {
        if pending[batch.scope] === batch { pending.removeValue(forKey: batch.scope) }
        if completed {
            if !batch.incomplete { lastBatches[batch.scope] = batch.inputs; lastMedia[batch.scope] = batch.identities }
            let hidden = hiddenMessageIds(in: batch.messages, accountPeerId: batch.account, scope: batch.scope)
            if hidden != batch.previousHidden { changed() }
            for message in batch.messages where hidden.contains(message.id) && !shouldHide(message, accountPeerId: batch.account, scope: batch.scope) {
                if let input = batch.inputs[message.id] {
                    let projection = RGAdProjection(disposition: .hide, text: "", entities: [], buttons: [], removedRanges: [], removedButtonIds: [], hideLinkPreview: true)
                    try? store.recordDetection(input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: batch.identities[message.id] ?? "", projection: projection)
                }
            }
        }
        for (token, completion) in batch.requests where !token.isCancelled { completion?() }
    }

    public func release(scope: Scope) {
        // Invalidate immediately, including a currently executing slice. Do not let its next
        // queued step repopulate a released list's cache.
        lock.lock(); requestedVersions.removeValue(forKey: scope); requestGenerations.removeValue(forKey: scope); lock.unlock()
        queue.async {
            self.lastBatches.removeValue(forKey: scope); self.lastMedia.removeValue(forKey: scope)
            self.pending.removeValue(forKey: scope)
            self.lock.lock(); self.cached.removeValue(forKey: scope); self.order.removeValue(forKey: scope); self.lock.unlock()
        }
    }

    private func prepared(_ message: Message, scope: Scope?) -> Cached? {
        lock.lock()
        let epoch = cacheEpoch
        var candidates = ((scope.map { [cached[$0]?[message.id]] } ?? []) + [cached[.history]?[message.id], cached[.pinned]?[message.id], sharedCache[message.id]]).compactMap { $0 }
        // A retained history window can outlive eviction from the shared reuse cache.
        if candidates.isEmpty && scope == nil { candidates = cached.values.compactMap { $0[message.id] } }
        if let value = candidates.first(where: { $0.validatedSource === message }) { lock.unlock(); return value }
        lock.unlock()
        guard !candidates.isEmpty else { return nil }
        let input = rgAdInput(message), mediaIdentity = rgAdMediaIdentity(message)
        guard let value = candidates.first(where: { $0.input == input && $0.mediaIdentity == mediaIdentity }) else { return nil }
        lock.lock()
        guard cacheEpoch == epoch else { lock.unlock(); return nil }
        value.validatedSource = message; lock.unlock()
        return value
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
        !canProject(message, accountPeerId: accountPeerId) || prepared(message, scope: scope)?.completed == true
    }

    /// Captionless members inherit only a complete ad verdict within the same Telegram album.
    /// A separate neighbouring picture, surviving caption/button, or reviewed media is preserved.
    public func hiddenMessageIds(in messages: [Message], accountPeerId: PeerId, scope: Scope? = nil) -> Set<MessageId> {
        struct Album: Hashable { let peerId: PeerId; let namespace: Int32; let key: Int64 }
        var values: [MessageId: Cached] = [:], hidden = Set<MessageId>()
        for message in messages {
            if let value = projection(message, accountPeerId: accountPeerId, scope: scope) {
                values[message.id] = value
                if value.projection?.disposition == .hide { hidden.insert(message.id) }
            }
        }
        var albums: [Album: [Message]] = [:]
        for message in messages {
            if let key = message.groupingKey { albums[Album(peerId: message.id.peerId, namespace: message.id.namespace, key: key), default: []].append(message) }
        }
        for members in albums.values {
            let captions = members.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.attributes.contains { $0 is ReplyMarkupMessageAttribute } }
            guard !captions.isEmpty, captions.allSatisfy({ hidden.contains($0.id) }),
                  members.allSatisfy({ values[$0.id]?.preservesMedia == false }) else { continue }
            for message in members where values[message.id]?.input.hasMedia == true { hidden.insert(message.id) }
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

// MARK: Regram — tie history/pinned work to its consuming signal, including disposal.
// Independent windows must not cancel each other merely because both display history.
public final class RGAdFilterWorkScope {
    public let scope: RGAdFilterSession.Scope
    private let session: RGAdFilterSession
    private let lock = NSLock()
    private var request: RGAdWorkRequest?
    public init(session: RGAdFilterSession, scope: RGAdFilterSession.Scope) {
        self.session = session; self.scope = scope
    }
    public func prepare(_ messages: [Message], accountPeerId: PeerId) {
        let next = session.prepare(messages, accountPeerId: accountPeerId, scope: scope)
        lock.lock(); let previous = request; request = next; lock.unlock()
        previous?.cancel()
    }
    deinit { request?.cancel(); session.release(scope: scope) }
}

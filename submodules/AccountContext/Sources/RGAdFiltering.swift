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
    init(_ source: Message, projection: RGAdProjection? = nil) { self.source = source; removedRanges = projection?.removedRanges ?? []; bodyLength = projection?.text.utf16.count ?? source.text.utf16.count }
    required init(decoder: PostboxDecoder) { source = nil; removedRanges = []; bodyLength = 0 }
    func encode(_ encoder: PostboxEncoder) {} // Display-only; never encode the original message.
}

public func rgAdOriginalMessage(_ message: Message) -> Message {
    (message.attributes.first { $0 is RGAdOriginalAttribute } as? RGAdOriginalAttribute)?.source ?? message
}

public func rgAdMessageWasFiltered(_ message: Message) -> Bool { message.attributes.contains { $0 is RGAdOriginalAttribute } }

/// An explicit reply quote carries a second copy of the original text. Only show it if its
/// original server range is intact; otherwise use the already cleaned message preview.
public func rgAdQuoteIsVisible(_ quote: EngineMessageReplyQuote, in message: Message) -> Bool {
    guard let attribute = message.attributes.first(where: { $0 is RGAdOriginalAttribute }) as? RGAdOriginalAttribute else { return true }
    guard attribute.bodyLength > 0, let original = attribute.source, let offset = quote.offset else { return false }
    let source = original.text as NSString
    guard offset >= 0, quote.text.utf16.count <= source.length, offset <= source.length - quote.text.utf16.count else { return false }
    let range = RGAdRange(offset, offset + quote.text.utf16.count)
    return source.substring(with: range.nsRange) == quote.text && !attribute.removedRanges.contains(where: { $0.intersects(range) })
}

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
    private final class WeakSession {
        weak var value: RGAdFilterSession?
        init(_ value: RGAdFilterSession) { self.value = value }
    }
    private static var sessions: [String: WeakSession] = [:]
    public static func get(_ context: AccountContext) -> RGAdFilterSession {
        registryLock.lock(); defer { registryLock.unlock() }
        let path = context.account.basePath
        if let session = sessions[path]?.value { return session }
        sessions = sessions.filter { $0.value.value != nil }
        let session = RGAdFilterSession(path: path)
        sessions[path] = WeakSession(session)
        return session
    }

    private let queue = DispatchQueue(label: "regram.ad-filter", qos: .utility)
    // MARK: Regram — an atomic Core ML call must never block cached/rule results or refreshes.
    private let inferenceQueue = DispatchQueue(label: "regram.ad-filter.inference", qos: .utility)
    private static let cacheIOQueue = DispatchQueue(label: "regram.ad-filter.cache-io", qos: .utility)
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
        var estimatedMemoryCost: Int {
            input.estimatedMemoryCost + (projection.map { 256 + $0.text.utf8.count * 2 + $0.entities.count * 96 + $0.buttons.flatMap { $0 }.count * 128 } ?? 0)
        }
    }
    private final class Batch {
        let scope: Scope; let generation: UInt64; let epoch: UInt64; let messages: [Message]; let account: PeerId
        let inputs: [MessageId: RGAdInput]; let identities: [MessageId: String]; let previousHidden: Set<MessageId>
        var cursor = 0
        var semantic: [SemanticWork] = []
        var semanticCursor = 0
        var finished = false
        var incomplete = false
        var requests: [(RGAdWorkRequest, (() -> Void)?, ((MessageId) -> Void)?)] = []
        init(scope: Scope, generation: UInt64, epoch: UInt64, messages: [Message], account: PeerId, inputs: [MessageId: RGAdInput], identities: [MessageId: String], previousHidden: Set<MessageId>) {
            self.scope = scope; self.generation = generation; self.epoch = epoch; self.messages = messages; self.account = account
            self.inputs = inputs; self.identities = identities; self.previousHidden = previousHidden
        }
    }
    private struct SemanticWork {
        let message: Message
        let group: String
        let sampleId: String?
        let preservesMedia: Bool
        let cacheKey: String?
    }
    private lazy var scheduler = RGAdWorkScheduler(queue: queue)
    private var pending: [Scope: Batch] = [:]
    private var sourceGroups: [PeerId: String] = [:]
    private var sharedCache = RGAdBoundedCache<MessageId, Cached>(countLimit: 2048, costLimit: 7 * 1024 * 1024)
    // Exact completed model outputs only. Policy and reviewed corrections are reapplied on reuse.
    private var semanticCache: RGAdSemanticCache?
    private var cacheWriteScheduled = false
    private var cacheEpoch: UInt64 = 0
    private var refreshWork: DispatchWorkItem?
    private var refreshDeadline: TimeInterval = 0
    private var lastRefresh: TimeInterval = 0
    private var retryNeeded = false
    private var retryScheduled = false
    private var foreground = true
    private var workConditions = RGAdWorkConditions()
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
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.lock.lock(); self.sharedCache.removeAll(); self.lock.unlock()
                self.sourceGroups.removeAll()
                self.flushSemanticCache()
                self.semanticCache?.removeAllFromMemory()
                self.scheduler.discardCancelled()
                self.inferenceQueue.async { RGAdSemanticClassifier.shared.reduceMemoryPressure() }
            }
        })
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

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        refreshWork?.cancel()
    }

    private func updateWorkConditions() {
        let conditions = RGAdWorkConditions(foreground: foreground, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: ProcessInfo.processInfo.thermalState.rawValue)
        workConditions = conditions
        scheduler.updateConditions(conditions)
        if !foreground { flushSemanticCache() }
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
        let samples = try store.load(reviewedOnly: true), salt = try store.salt(), enabled = try store.isEnabled()
        self.knowledge = RGAdPolicy.Knowledge(samples: samples); self.salt = salt; self.enabled = enabled; self.lastBatches = [:]; self.lastMedia = [:]
        sourceGroups.removeAll()
        if semanticCache == nil {
            let cache = RGAdSemanticCache(accountDirectory: store.directory.deletingLastPathComponent(), namespace: RGAdSemanticCache.bundledNamespace(), salt: salt)
            cache.load(); semanticCache = cache
        }
        pending.removeAll()
        retryNeeded = false
        lock.lock()
        cacheEpoch &+= 1
        cached.removeAll(); order.removeAll(); sharedCache.removeAll()
        lock.unlock()
        scheduler.discardCancelled()
    }

    private func scheduleCacheWrite() {
        guard !cacheWriteScheduled else { return }
        cacheWriteScheduled = true
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.cacheWriteScheduled = false; self.flushSemanticCache()
        }
    }

    private func flushSemanticCache() {
        if let writer = semanticCache?.takeWriter() { Self.cacheIOQueue.async { writer() } }
    }
    private func changed(urgent: Bool = false) {
        // Show a current-chat verdict promptly, while coalescing the remaining batch.
        // Urgent updates can advance an existing timer, never postpone a ready result.
        let now = ProcessInfo.processInfo.systemUptime
        let delay = max(0.016, lastRefresh + (urgent ? 0.016 : 0.05) - now)
        let deadline = now + delay
        if refreshWork != nil && refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        refreshDeadline = deadline
        let work = DispatchWorkItem {
            self.refreshWork = nil
            self.lastRefresh = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { NotificationCenter.default.post(name: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil) }
        }
        refreshWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
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
        prepareMessages(messages, accountPeerId: accountPeerId, scope: scope, progress: nil, completion: completion)
    }

    // MARK: Regram — progress is scoped to a live consumer and includes normal verdicts.
    @discardableResult public func prepareProgressively(_ messages: [Message], accountPeerId: PeerId, scope: Scope, progress: @escaping (MessageId) -> Void, completion: @escaping () -> Void) -> RGAdWorkRequest {
        prepareMessages(messages, accountPeerId: accountPeerId, scope: scope, progress: progress, completion: completion)
    }

    private func prepareMessages(_ messages: [Message], accountPeerId: PeerId, scope: Scope, progress: ((MessageId) -> Void)?, completion: (() -> Void)?) -> RGAdWorkRequest {
        let token = RGAdWorkRequest()
        // One loaded reply target per message, one hop only. Do not fetch an unbounded
        // reply chain or spend homepage inference on reply headers that are not displayed.
        let roots: [Message]
        let includeReplies: Bool
        switch scope {
        case .chatList: roots = Array(messages.prefix(capacity(scope))); includeReplies = false
        default: roots = Array(messages.suffix(capacity(scope)).reversed()); includeReplies = true
        }
        var sources: [Message] = [], seen = Set<MessageId>(), replyCount = 0
        for message in roots {
            if seen.insert(message.id).inserted { sources.append(message) }
            if includeReplies, replyCount < 128, canProjectReply(in: message, accountPeerId: accountPeerId),
               let reply = message.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute,
               let target = message.associatedMessages[reply.messageId], seen.insert(target.id).inserted {
                sources.append(rgAdOriginalMessage(target)); replyCount += 1
            }
        }
        var versions: [MessageId: UInt32] = [:]
        for message in sources { versions[message.id] = message.stableVersion }
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
            // Explicit opt-outs and temporary original-message mode must not consume model work.
            let eligible = self.enabled ? sources.filter { self.canProject($0, accountPeerId: accountPeerId) } : []
            var inputs: [MessageId: RGAdInput] = [:], identities: [MessageId: String] = [:]
            for message in eligible { inputs[message.id] = rgAdInput(message); identities[message.id] = rgAdMediaIdentity(message) }
            if let batch = self.pending[scope], batch.generation == generation, batch.inputs == inputs, batch.identities == identities {
                batch.requests.removeAll { $0.0.isCancelled }
                batch.requests.append((token, completion, progress)); return
            }
            guard inputs != self.lastBatches[scope] || identities != self.lastMedia[scope] else { completion?(); return }
            let batch = Batch(scope: scope, generation: generation, epoch: self.cacheEpoch, messages: eligible, account: accountPeerId, inputs: inputs, identities: identities,
                              previousHidden: self.hiddenMessageIds(in: eligible, accountPeerId: accountPeerId, scope: scope))
            batch.requests.append((token, completion, progress)); self.pending[scope] = batch
            self.prepareFastResults(batch)
        }
        return token
    }

    private func capacity(_ scope: Scope) -> Int {
        switch scope { case .history, .historyView: return 512; case .pinned, .pinnedView: return 64; case .chatList: return 8192 }
    }

    private func priority(_ scope: Scope) -> Int {
        switch scope { case .pinned, .pinnedView: return 2; case .history, .historyView: return 1; case .chatList: return 0 }
    }

    private func isLive(_ batch: Batch) -> Bool {
        !batch.finished && pending[batch.scope] === batch && cacheEpoch == batch.epoch
            && isCurrent(batch.scope, generation: batch.generation) && batch.requests.contains { !$0.0.isCancelled }
    }

    // MARK: Regram — bounded, inexpensive preparation runs independently of model cooldown.
    // Unknown messages remain unprepared; a deterministic partial cut is not a normal verdict.
    private func prepareFastResults(_ batch: Batch) {
        guard isLive(batch) else { finish(batch, completed: false); return }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.004
        var count = 0
        repeat {
            if batch.cursor == batch.messages.count { break }
            let message = batch.messages[batch.cursor]
            autoreleasepool { prepareFastResult(message, batch: batch) }
            batch.cursor += 1; count += 1
        } while count < 16 && ProcessInfo.processInfo.systemUptime < deadline && isLive(batch)
        if batch.cursor < batch.messages.count {
            queue.async { self.prepareFastResults(batch) }
        } else if batch.semantic.isEmpty {
            finish(batch, completed: true)
        } else {
            scheduler.enqueueAsync(priority: priority(batch.scope), cancelled: { !self.isLive(batch) }, step: { done in
                self.processSemantic(batch) {
                    if !self.isLive(batch) { self.finish(batch, completed: false); done(true); return }
                    batch.semanticCursor += 1
                    if batch.semanticCursor == batch.semantic.count { self.finish(batch, completed: true); done(true) }
                    else { done(false) }
                }
            }, onCancel: { self.finish(batch, completed: false) })
        }
    }

    private func reusable(_ message: Message, batch: Batch) -> Cached? {
        guard let input = batch.inputs[message.id] else { return nil }
        let mediaIdentity = batch.identities[message.id] ?? ""
        lock.lock()
        let old = cached[batch.scope]?[message.id]
        let reuse = [old, sharedCache[message.id]].compactMap { $0 }.first { $0.completed && $0.input == input && $0.mediaIdentity == mediaIdentity }
        lock.unlock()
        return reuse
    }

    private func prepareFastResult(_ message: Message, batch: Batch) {
        guard isLive(batch), let input = batch.inputs[message.id] else { return }
        if let reuse = reusable(message, batch: batch) { publish(reuse, message: message, batch: batch); return }
        let group: String
        if let existing = sourceGroups[message.id.peerId] { group = existing }
        else {
            if sourceGroups.count >= 1024 { sourceGroups.removeAll() }
            group = RGAdSampleStore.sourceGroup(salt: salt, peerId: message.id.peerId.toInt64()); sourceGroups[message.id.peerId] = group
        }
        let sampleId = knowledge.requiresSnapshot(for: input)
            ? try? RGAdSampleStore.sampleId(input: input, salt: salt, messageKey: rgAdSampleKey(message), mediaIdentity: batch.identities[message.id] ?? "") : nil
        let preservesMedia = knowledge.preservesMedia(input, sourceGroup: group, sampleId: sampleId)
        do {
            let initial = try knowledge.prepare(input, sourceGroup: group, sampleId: sampleId)
            let cacheKey = initial.isFinal ? nil : semanticCache?.key(for: input)
            if !initial.isFinal, let semantic = semanticCache?.result(for: cacheKey, input: input) {
                let result = try knowledge.project(input, sourceGroup: group, semantic: semantic, sampleId: sampleId)
                accept(result, message: message, batch: batch, completed: true, preservesMedia: preservesMedia)
                return
            }
            accept(initial.projection, message: message, batch: batch, completed: initial.isFinal, preservesMedia: preservesMedia, record: initial.isFinal)
            if !initial.isFinal { batch.semantic.append(SemanticWork(message: message, group: group, sampleId: sampleId, preservesMedia: preservesMedia, cacheKey: cacheKey)) }
        } catch RGAdFilterError.budgetExceeded {
            batch.incomplete = true; retryNeeded = true; scheduleRetry()
        } catch {
            // Unsupported input shapes/sizes retain the original, as before. Retrying them
            // cannot help and would strand a homepage fallback behind an impossible verdict.
            accept(nil, message: message, batch: batch, completed: true, preservesMedia: preservesMedia)
        }
    }

    private func processSemantic(_ batch: Batch, completion: @escaping () -> Void) {
        guard isLive(batch), batch.semanticCursor < batch.semantic.count else { completion(); return }
        let work = batch.semantic[batch.semanticCursor], message = batch.semantic[batch.semanticCursor].message
        // Another scope may have finished this exact message while it was waiting for admission.
        if let reuse = reusable(message, batch: batch) { publish(reuse, message: message, batch: batch); completion(); return }
        guard let input = batch.inputs[message.id] else { completion(); return }
        if let semantic = semanticCache?.result(for: work.cacheKey, input: input) {
            do {
                let result = try knowledge.project(input, sourceGroup: work.group, semantic: semantic, sampleId: work.sampleId)
                accept(result, message: message, batch: batch, completed: true, preservesMedia: work.preservesMedia)
            } catch RGAdFilterError.budgetExceeded { batch.incomplete = true; retryNeeded = true; scheduleRetry() }
            catch { accept(nil, message: message, batch: batch, completed: true, preservesMedia: work.preservesMedia) }
            completion(); return
        }
        let knowledge = self.knowledge
        // MARK: Regram — propagate the visible scope's QoS through the asynchronous model hop.
        let interactive = workConditions.interactive && priority(batch.scope) > 0
        inferenceQueue.async(execute: DispatchWorkItem(qos: interactive ? .userInitiated : .utility, flags: .enforceQoS) {
            let result: (RGAdProjection?, RGAdSemanticResult) = autoreleasepool {
                let semantic = RGAdSemanticClassifier.shared.predict(input)
                do { return (try knowledge.project(input, sourceGroup: work.group, semantic: semantic, sampleId: work.sampleId), semantic) }
                catch RGAdFilterError.budgetExceeded { return (nil, RGAdSemanticResult(completed: false)) }
                catch { return (nil, RGAdSemanticResult(completed: semantic.completed)) }
            }
            self.queue.async {
                // A superseded viewport may still contain the same message in its replacement.
                // Reuse a complete prediction, but never publish it into the retired viewport.
                if self.cacheEpoch == batch.epoch, result.0 != nil, result.1.completed {
                    self.semanticCache?.insert(result.1, for: work.cacheKey, input: input)
                    self.scheduleCacheWrite()
                }
                // Cancellation, edits and corrections may arrive during the atomic prediction.
                guard self.isLive(batch), self.canProject(message, accountPeerId: batch.account) else { completion(); return }
                if !result.1.completed { batch.incomplete = true; self.retryNeeded = true; self.scheduleRetry() }
                self.accept(result.0, message: message, batch: batch, completed: result.1.completed, preservesMedia: work.preservesMedia)
                completion()
            }
        })
    }

    private func accept(_ result: RGAdProjection?, message: Message, batch: Batch, completed: Bool, preservesMedia: Bool, record: Bool = true) {
        guard isLive(batch), let input = batch.inputs[message.id] else { return }
        let projected = result?.disposition == .keep ? nil : result
        // A pending or unavailable model cannot release an unclassified fallback preview.
        guard completed || projected != nil else { return }
        let mediaIdentity = batch.identities[message.id] ?? ""
        lock.lock(); let old = cached[batch.scope]?[message.id]; lock.unlock()
        var published = true
        if old?.input != input || old?.mediaIdentity != mediaIdentity || old?.projection != projected
            || old?.completed != completed || old?.preservesMedia != preservesMedia {
            revision &+= 1
            let value = Cached(input: input, mediaIdentity: mediaIdentity, projection: projected, revision: revision,
                               preservesMedia: preservesMedia, source: message, completed: completed)
            published = publish(value, message: message, batch: batch)
        }
        if record, published, let projected {
            // Publishing/progress never waits for the automatic sample write. Recheck the
            // settings epoch before recording; a correction may already have replaced it.
            let epoch = batch.epoch, account = batch.account
            queue.async {
                guard self.cacheEpoch == epoch, self.canProject(message, accountPeerId: account) else { return }
                try? self.store.recordDetection(input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: mediaIdentity, projection: projected)
            }
        }
    }

    @discardableResult private func publish(_ value: Cached, message: Message, batch: Batch) -> Bool {
        guard isLive(batch) else { return false }
        let scope = batch.scope
        lock.lock()
        guard cacheEpoch == batch.epoch, requestGenerations[scope] == batch.generation else { lock.unlock(); return false }
        let old = cached[scope]?[message.id]
        if cached[scope]?[message.id] == nil {
            if order[scope, default: []].count >= capacity(scope) + 128, let evicted = order[scope]?.removeFirst() { cached[scope]?.removeValue(forKey: evicted) }
            order[scope, default: []].append(message.id)
        }
        cached[scope, default: [:]][message.id] = value
        sharedCache.insert(value, for: message.id, cost: value.estimatedMemoryCost)
        lock.unlock()
        if old !== value && (old?.projection != nil || value.projection != nil) {
            changed(urgent: priority(scope) == 2 || batch.cursor <= 1)
        }
        if old !== value {
            for (token, _, progress) in batch.requests where !token.isCancelled { progress?(message.id) }
        }
        return true
    }

    private func finish(_ batch: Batch, completed: Bool) {
        guard !batch.finished else { return }
        let completed = completed && isLive(batch)
        batch.finished = true
        if pending[batch.scope] === batch { pending.removeValue(forKey: batch.scope) }
        if completed {
            if !batch.incomplete { lastBatches[batch.scope] = batch.inputs; lastMedia[batch.scope] = batch.identities }
            // Keep this window's prepared values, not every window visited in its lifetime.
            lock.lock()
            cached[batch.scope] = cached[batch.scope]?.filter { batch.inputs[$0.key] != nil }
            order[batch.scope] = order[batch.scope]?.filter { batch.inputs[$0] != nil }
            lock.unlock()
            let hidden = hiddenMessageIds(in: batch.messages, accountPeerId: batch.account, scope: batch.scope)
            if hidden != batch.previousHidden { changed(urgent: priority(batch.scope) > 0) }
            for message in batch.messages where hidden.contains(message.id) && !shouldHide(message, accountPeerId: batch.account, scope: batch.scope) {
                if let input = batch.inputs[message.id] {
                    let projection = RGAdProjection(disposition: .hide, text: "", entities: [], buttons: [], removedRanges: [], removedButtonIds: [], hideLinkPreview: true)
                    try? store.recordDetection(input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: batch.identities[message.id] ?? "", projection: projection)
                }
            }
        }
        for (token, completion, _) in batch.requests where !token.isCancelled { completion?() }
    }

    public func release(scope: Scope) {
        // Invalidate immediately, including a currently executing slice. Do not let its next
        // queued step repopulate a released list's cache.
        lock.lock(); requestedVersions.removeValue(forKey: scope); requestGenerations.removeValue(forKey: scope); lock.unlock()
        queue.async {
            self.lastBatches.removeValue(forKey: scope); self.lastMedia.removeValue(forKey: scope)
            self.pending.removeValue(forKey: scope)
            self.lock.lock(); self.cached.removeValue(forKey: scope); self.order.removeValue(forKey: scope); self.lock.unlock()
            self.scheduler.discardCancelled()
        }
    }

    private func prepared(_ message: Message, scope: Scope?) -> Cached? {
        lock.lock()
        let epoch = cacheEpoch
        var candidates = ((scope.map { [cached[$0]?[message.id]] } ?? []) + [cached[.history]?[message.id], cached[.pinned]?[message.id], sharedCache[message.id]]).compactMap { $0 }
        // A retained history window can outlive eviction from the shared reuse cache.
        if candidates.isEmpty && scope == nil { candidates = cached.values.compactMap { $0[message.id] } }
        // Another live scope may finish while this scope still holds a preliminary cut.
        // Its complete shared verdict is usable immediately, without waiting for our scheduler.
        if let value = candidates.first(where: { $0.completed && $0.validatedSource === message }) { lock.unlock(); return value }
        let validated = candidates.first(where: { $0.validatedSource === message })
        if let value = validated, !candidates.contains(where: { $0.completed }) { lock.unlock(); return value }
        lock.unlock()
        guard !candidates.isEmpty else { return nil }
        let input = validated?.input ?? rgAdInput(message), mediaIdentity = validated?.mediaIdentity ?? rgAdMediaIdentity(message)
        guard let value = candidates.first(where: { $0.completed && $0.input == input && $0.mediaIdentity == mediaIdentity })
            ?? candidates.first(where: { $0.input == input && $0.mediaIdentity == mediaIdentity }) else { return nil }
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
        return allowsFiltering(peerId: message.id.peerId, accountPeerId: accountPeerId)
    }

    private func allowsFiltering(peerId: PeerId, accountPeerId: PeerId) -> Bool {
        let settings = RGSimpleSettings.shared
        return settings.chatPreferences(accountId: accountPeerId.toInt64(), peerId: peerId.toInt64()).adFiltering != false
            && !settings.temporarilyVisiblePeerIds(accountId: accountPeerId.toInt64()).contains(peerId.toInt64())
    }

    private func canProjectReply(in message: Message, accountPeerId: PeerId) -> Bool {
        rgCanCorrectAds(message) && rgIsAdFilteringPeer(message) && message.adAttribute == nil
            && message.activeEphemeralReplacementMessage == nil && allowsFiltering(peerId: message.id.peerId, accountPeerId: accountPeerId)
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
        let original = rgAdOriginalMessage(message)
        let body = displayBody(original, accountPeerId: accountPeerId, scope: scope)
        // A normal reply must survive its target being hidden. Clean its preview using the
        // target's own verdict and peer policy, without classifying quoted text as a new ad.
        guard canProjectReply(in: original, accountPeerId: accountPeerId),
              let reply = original.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute,
              let target = original.associatedMessages[reply.messageId], target.id != original.id,
              let value = projection(rgAdOriginalMessage(target), accountPeerId: accountPeerId, scope: scope),
              let projected = value.projection else { return body }
        var attributes = body.attributes
        var associated = body.associatedMessages
        if projected.disposition == .hide {
            // Removing the display header also removes its thumbnail and tappable ad target.
            // Keep the original reply metadata behind the display-only restoration attribute.
            attributes.removeAll { $0 is ReplyMessageAttribute || $0 is QuotedReplyMessageAttribute }
        } else {
            let preview = displayBody(rgAdOriginalMessage(target), accountPeerId: accountPeerId, scope: scope)
            associated[reply.messageId] = preview
            let keepQuote = reply.quote.map { rgAdQuoteIsVisible($0, in: preview) } ?? false
            attributes = attributes.compactMap { attribute in
                if attribute is QuotedReplyMessageAttribute { return nil }
                if attribute is ReplyMessageAttribute, reply.quote != nil, !keepQuote {
                    return ReplyMessageAttribute(messageId: reply.messageId, threadMessageId: reply.threadMessageId, quote: nil, isQuote: false, innerSubject: reply.innerSubject)
                }
                return attribute
            }
        }
        if !attributes.contains(where: { $0 is RGAdOriginalAttribute }) { attributes.append(RGAdOriginalAttribute(original)) }
        return body.withUpdatedAttributes(attributes).withUpdatedAssociatedMessages(associated)
            .withUpdatedStableVersion(stableVersion: body.stableVersion &+ 0x4000_0000 &+ value.revision)
    }

    private func displayBody(_ message: Message, accountPeerId: PeerId, scope: Scope?) -> Message {
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
        if projection.disposition == .hide { result = result.withUpdatedMedia([]) }
        else if projection.hideLinkPreview { result = result.withUpdatedMedia(message.media.filter { !($0 is TelegramMediaWebpage) }) }
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

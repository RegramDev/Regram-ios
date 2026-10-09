// MARK: Regram — manual @username input uses the same native mention entities as the picker.
import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import TextFormat
import RGSimpleSettings

private struct RGMentionCandidate {
    let range: Range<Int>
    let username: String
}
private func rgMentionCandidates(text: String, entities: [MessageTextEntity]) -> [RGMentionCandidate] {
    let detected = generateTextEntities(text, enabledTypes: .all, currentEntities: entities)
    let string = text as NSString
    return detected.compactMap { entity in
        guard case .Mention = entity.type, entity.range.count > 1, entity.range.lowerBound >= 0, entity.range.upperBound <= string.length else { return nil }
        for other in detected where other.range.overlaps(entity.range) {
            switch other.type {
            case .Code, .Pre, .Url, .Email, .TextUrl, .TextMention, .CustomEmoji, .BotCommand: return nil
            default: break
            }
        }
        let name = string.substring(with: NSRange(location: entity.range.lowerBound + 1, length: entity.range.count - 1)).lowercased()
        return RGMentionCandidate(range: entity.range, username: name)
    }
}

/// Resolve each unique username once per batch. The FIFO also preserves ordering across rapid sends.
final class RGNicknameMentionQueue {
    private let context: AccountContext
    private var jobs: [([EnqueueMessage], ([EnqueueMessage]) -> Void)] = []
    private var working = false
    private let disposable = MetaDisposable()
    init(context: AccountContext) { self.context = context }
    deinit { self.disposable.dispose() }
    func resolve(_ messages: [EnqueueMessage], completion: @escaping ([EnqueueMessage]) -> Void) {
        self.jobs.append((messages, completion))
        self.drain()
    }
    private func drain() {
        guard !self.working, !self.jobs.isEmpty else { return }
        self.working = true
        let (messages, completion) = self.jobs.removeFirst()
        var names: [String] = []
        if RGSimpleSettings.shared.mentionAsUserIdLink {
            for message in messages {
                guard case let .message(text, attributes, _, _, _, _, _, _, _, _) = message else { continue }
                let entities = attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap { $0.entities }
                for candidate in rgMentionCandidates(text: text, entities: entities) where !names.contains(candidate.username) {
                    if names.count < 16 { names.append(candidate.username) }
                }
            }
        }
        let signals: [Signal<(String, EnginePeer?), NoError>] = names.map { name in
            self.context.engine.peers.resolvePeerByName(name: name, referrer: nil, ageLimit: 10)
            |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                if case let .result(peer) = result { return .single(peer) }
                return .complete()
            }
            |> take(1)
            |> timeout(4.0, queue: .mainQueue(), alternate: .single(nil))
            |> map { (name, $0) }
        }
        let resolved: Signal<[(String, EnginePeer?)], NoError> = signals.isEmpty ? .single([]) : combineLatest(signals)
        self.disposable.set((resolved |> deliverOnMainQueue).start(next: { [self] values in
            var peers: [String: EnginePeer] = [:]
            for (name, peer) in values {
                if let peer, case .user = peer { peers[name] = peer }
            }
            let updated = messages.map { message -> EnqueueMessage in
                guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else { return message }
                let entities = attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap { $0.entities }
                var replacements: [RGMentionReplacementPolicy.Replacement] = []
                var mentions: [(Range<Int>, PeerId)] = []
                var textLength = text.utf16.count
                let isCaption = mediaReference?.media is TelegramMediaImage || mediaReference?.media is TelegramMediaFile
                let limit = isCaption ? Int(self.context.userLimits.maxCaptionLength) : 4096
                for candidate in rgMentionCandidates(text: text, entities: entities) {
                    guard let peer = peers[candidate.username] else { continue }
                    guard case let .user(user) = peer else { continue }
                    let fullName = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    let title = (fullName.isEmpty ? peer.compactDisplayTitle : fullName).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, !replacements.contains(where: { $0.range == candidate.range }) else { continue }
                    let updatedLength = textLength + title.utf16.count - candidate.range.count
                    guard updatedLength <= limit else { continue }
                    textLength = updatedLength
                    replacements.append(.init(range: candidate.range, text: title))
                    mentions.append((candidate.range, peer.id))
                }
                guard !replacements.isEmpty else { return message }
                var updatedEntities = entities.compactMap { entity -> MessageTextEntity? in
                    if case .Mention = entity.type, mentions.contains(where: { $0.0 == entity.range }) { return nil }
                    let range = RGMentionReplacementPolicy.remap(entity.range, replacements: replacements)
                    guard !range.isEmpty else { return nil }
                    return MessageTextEntity(range: range, type: entity.type)
                }
                for (range, id) in mentions {
                    updatedEntities.append(MessageTextEntity(range: RGMentionReplacementPolicy.remap(range, replacements: replacements), type: .TextMention(peerId: id)))
                }
                var updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
                updatedAttributes.append(TextEntitiesMessageAttribute(entities: updatedEntities))
                return .message(text: RGMentionReplacementPolicy.replacing(text, replacements: replacements), attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
            }
            completion(updated)
            // Starting the next signal asynchronously avoids replacing a subscription during its
            // synchronous initial emission. The queued job keeps the send's snapshot intact.
            Queue.mainQueue().async { [self] in
                self.disposable.set(nil)
                self.working = false
                self.drain()
            }
        }))
    }
}

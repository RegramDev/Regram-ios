// MARK: Regram — type or pick @username to insert the same native nickname mention as long press.
import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import TextFormat
import RGSimpleSettings

func rgNicknameMentionText(peer: EnginePeer, suffix: String) -> NSAttributedString? {
    guard RGSimpleSettings.shared.mentionAsUserIdLink, case let .user(user) = peer else { return nil }
    let fullName = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    let title = fullName.isEmpty ? peer.compactDisplayTitle : fullName
    guard !title.isEmpty else { return nil }
    let result = NSMutableAttributedString(string: title, attributes: [ChatTextInputAttributes.textMention: ChatTextInputTextMentionAttribute(peerId: peer.id)])
    result.append(NSAttributedString(string: suffix))
    return result
}

private struct RGMentionCandidate {
    let range: NSRange
    let username: String
}
private func rgMentionCandidates(state: ChatTextInputState) -> [RGMentionCandidate] {
    let input = state.inputText
    // Detect usernames independently of formatting: upstream suppresses detection inside ANY
    // existing entity, including bold/italic spans. Only semantic/code spans should exclude them.
    let detected = generateTextEntities(input.string, enabledTypes: .all)
    let entities = generateChatInputTextEntities(input) + detected
    let string = input.string as NSString
    var seen = Set<Int>()
    return detected.compactMap { entity in
        guard case .Mention = entity.type, entity.range.count > 1, entity.range.lowerBound >= 0, entity.range.upperBound <= string.length else { return nil }
        for other in entities where other.range.overlaps(entity.range) {
            switch other.type {
            case .Code, .Pre, .Url, .Email, .TextUrl, .TextMention, .CustomEmoji, .BotCommand: return nil
            default: break
            }
        }
        // A caret in the middle of a username is still editing that token.
        if entity.range.contains(state.selectionRange.lowerBound) && state.selectionRange.lowerBound != entity.range.lowerBound { return nil }
        guard seen.insert(entity.range.lowerBound).inserted else { return nil }
        let range = NSRange(location: entity.range.lowerBound, length: entity.range.count)
        let username = string.substring(with: NSRange(location: range.location + 1, length: range.length - 1)).lowercased()
        return RGMentionCandidate(range: range, username: username)
    }
}

/// Debounce typing and discard stale lookups. Conversion is applied to the structural draft, not to
/// the outgoing message, so rich text, cursor position and native mention rendering agree.
final class RGNicknameMentionInputResolver {
    private let context: AccountContext
    private let disposable = MetaDisposable()
    init(context: AccountContext) { self.context = context }
    deinit { self.disposable.dispose() }

    func update(state: ChatTextInputState, canApply: @escaping () -> Bool, apply: @escaping (ChatTextInputState) -> Void) {
        self.disposable.set(nil)
        guard RGSimpleSettings.shared.mentionAsUserIdLink, state.selectionRange.isEmpty else { return }
        let candidates = rgMentionCandidates(state: state)
        var names: [String] = []
        for candidate in candidates where !names.contains(candidate.username) {
            if names.count < 16 { names.append(candidate.username) }
        }
        guard !names.isEmpty else { return }
        let signal = (Signal<Void, NoError>.single(()) |> delay(0.65, queue: .mainQueue()))
        |> mapToSignal { [context] _ -> Signal<[(String, EnginePeer?)], NoError> in
            return combineLatest(names.map { name -> Signal<(String, EnginePeer?), NoError> in
                context.engine.peers.resolvePeerByName(name: name, referrer: nil, ageLimit: 10)
                |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                    if case let .result(peer) = result { return .single(peer) }
                    return .complete()
                }
                |> take(1)
                |> timeout(4.0, queue: .mainQueue(), alternate: .single(nil))
                |> map { (name, $0) }
            })
        }
        self.disposable.set((signal |> deliverOnMainQueue).start(next: { values in
            guard RGSimpleSettings.shared.mentionAsUserIdLink, canApply() else { return }
            var peers: [String: EnginePeer] = [:]
            for (name, peer) in values {
                guard let peer, case let .user(user) = peer else { continue }
                let aliases = user.usernames.map { $0.username.lowercased() } + [user.username?.lowercased()].compactMap { $0 }
                guard aliases.contains(name) else { continue }
                peers[name] = peer
            }
            var updated = state
            var changes: [RGMentionReplacementPolicy.Replacement] = []
            let original = state.inputText
            for candidate in candidates.sorted(by: { $0.range.location > $1.range.location }) {
                guard let peer = peers[candidate.username], let nickname = rgNicknameMentionText(peer: peer, suffix: "") else { continue }
                let atEnd = NSMaxRange(candidate.range) == original.length && state.selectionRange.lowerBound == original.length
                let replacement = NSMutableAttributedString(attributedString: nickname)
                if atEnd { replacement.append(NSAttributedString(string: " ")) }
                let inherited = original.attributes(at: candidate.range.location, effectiveRange: nil)
                for key in [ChatTextInputAttributes.bold, ChatTextInputAttributes.italic, ChatTextInputAttributes.underline, ChatTextInputAttributes.strikethrough, ChatTextInputAttributes.spoiler] {
                    if let value = inherited[key] { replacement.addAttribute(key, value: value, range: NSRange(location: 0, length: replacement.length)) }
                }
                updated = updated.replacingFlatRange(candidate.range, with: replacement)
                changes.append(.init(range: candidate.range.location..<NSMaxRange(candidate.range), text: replacement.string))
            }
            guard !changes.isEmpty else { return }
            let caret = RGMentionReplacementPolicy.remap(state.selectionRange, replacements: changes)
            // Rebuild from structural content, never the lossy attributed-string projection.
            updated = ChatTextInputState(content: updated.content, selectionRange: caret)
            apply(updated)
        }))
    }
}

private func rgHasMarkedText(in view: UIView) -> Bool {
    if let input = view as? UITextInput, input.markedTextRange != nil { return true }
    return view.subviews.contains { rgHasMarkedText(in: $0) }
}

extension ChatControllerImpl {
    func rgUpdateNicknameMentionInput() {
        let snapshot = self.presentationInterfaceState.interfaceState.effectiveInputState
        self.rgNicknameMentionInputResolver.update(state: snapshot, canApply: { [weak self] in
            guard let self, self.isNodeLoaded, self.presentationInterfaceState.interfaceState.effectiveInputState == snapshot else { return false }
            if let input = self.chatDisplayNode.textInputPanelNode?.richTextInputNode {
                return !rgHasMarkedText(in: input.asNode.view)
            }
            return false
        }, apply: { [weak self] updated in
            self?.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                state.updatedInterfaceState { $0.withUpdatedEffectiveInputState(updated) }
            })
        })
    }
}

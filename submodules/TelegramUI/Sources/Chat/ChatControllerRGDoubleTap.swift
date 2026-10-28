import Foundation
import TelegramCore
import AccountContext
import ChatPresentationInterfaceState
import ChatControllerInteraction
import TextSelectionNode
import RGSimpleSettings
import TextProcessingScreen
import ChatRichTextEditorComposer
import SwiftSignalKit
import UndoUI

// MARK: Regram — the double-tap actions that need the chat controller (RGDoubleTapMessageAction).
// The item node handles the reaction and the menu itself and hands the rest back here.
extension ChatControllerImpl {
    func rgCanEditMessage(_ message: EngineRawMessage) -> Bool {
        if case .pinnedMessages = self.subject {
            return false
        }
        // A basic group's messages shown in the supergroup it migrated to cannot be edited there.
        let isMigrated = self.presentationInterfaceState.renderedPeer?.peer is TelegramChannel && message.id.peerId.namespace == Namespaces.Peer.CloudGroup
        if isMigrated {
            return false
        }
        return canEditMessage(context: self.context, limitsConfiguration: self.context.currentLimitsConfiguration.with { EngineConfiguration.Limits($0) }, message: message)
    }

    func rgPerformMessageDoubleTapAction(message: EngineRawMessage, actionRawValue: String) {
        guard self.isNodeLoaded, let action = RGSimpleSettings.MessageDoubleTapActionV2(rawValue: actionRawValue) else {
            return
        }
        var threadId: Int64?
        if case let .replyThread(replyThreadMessage) = self.chatLocation {
            threadId = replyThreadMessage.threadId
        }
        switch action {
        case .disabled, .sendReaction, .showReactions:
            break
        case .reply:
            if let controllerInteraction = self.controllerInteraction, case .reply = controllerInteraction.canSetupReply(message) {
                controllerInteraction.setupReply(message.id)
            }
        case .repeatMessage:
            guard message.id.namespace == Namespaces.Message.Cloud, canSendMessagesToChat(self.presentationInterfaceState), !message.isCopyProtected() else {
                return
            }
            // Local content-saving overrides cannot change the server's forwarding permission.
            if message.flags.contains(.CopyProtected) { return }
            if let channel = message.peers[message.id.peerId] as? TelegramChannel, channel.flags.contains(.copyProtectionEnabled) { return }
            if let group = message.peers[message.id.peerId] as? TelegramGroup, group.flags.contains(.copyProtectionEnabled) { return }
            rgSendRepeatForward(context: self.context, peerId: message.id.peerId, threadId: threadId, messageIds: [message.id])
        case .repeatWithoutQuote:
            guard canSendMessagesToChat(self.presentationInterfaceState), let items = rgRepeatCopyItems([message]) else {
                return
            }
            rgSendRepeatCopy(context: self.context, peerId: message.id.peerId, threadId: threadId, items: items, failed: { [weak self] in
                guard let self else { return }
                self.controllerInteraction?.displayUndo(.info(title: nil, text: self.presentationData.strings.Login_UnknownError, timeout: nil, customUndoText: nil))
            })
        case .translate:
            guard !message.rgTextContent.isEmpty, message.id.peerId.namespace != Namespaces.Peer.SecretChat else {
                return
            }
            if let rich = message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute {
                self.chatDisplayNode.dismissInput()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let resolved: RichTextMessageAttribute?
                    if (rich.fullInstantPage ?? rich.instantPage).isComplete { resolved = rich }
                    else { resolved = await (self.context.engine.messages.requestFullRichText(id: message.id) |> take(1) |> timeout(20, queue: .mainQueue(), alternate: .single(nil))).get() }
                    guard let resolved, (resolved.fullInstantPage ?? resolved.instantPage).isComplete else {
                        self.controllerInteraction?.displayUndo(.info(title: nil, text: self.presentationData.strings.Login_UnknownError, timeout: nil, customUndoText: nil))
                        return
                    }
                    self.push(await TextProcessingScreen(context: self.context, sourceMessageId: message.id,
                        mode: .translate(fromLanguage: nil, applyResult: nil),
                        inputText: .rich(instantPage: resolved.fullInstantPage ?? resolved.instantPage),
                        copyResult: message.isCopyProtected() ? nil : { storeComposedRichMessageInPasteboard($0) },
                        translateChat: { [weak self] language in
                            self?.interfaceInteraction?.changeTranslationLanguage(language)
                            self?.interfaceInteraction?.toggleTranslation(.translated)
                        }))
                }
                return
            }
            self.controllerInteraction?.performTextSelectionAction(message, !message.isCopyProtected(), NSAttributedString(string: message.text), message.textEntitiesAttribute?.entities, .translate)
        case .edit:
            guard self.rgCanEditMessage(message) else {
                return
            }
            if message.media.contains(where: { $0 is TelegramMediaTodo }) {
                self.interfaceInteraction?.editTodoMessage(message.id, nil, false)
            } else {
                self.interfaceInteraction?.setupEditMessage(message.id, { _ in })
            }
        }
    }
}

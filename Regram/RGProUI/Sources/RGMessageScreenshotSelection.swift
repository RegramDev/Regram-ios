// MARK: Regram — render every selected message, including those outside the visible history.
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import Postbox
import SwiftSignalKit
import AvatarNode
import ChatMessageItemView
import LocalizedPeerData
import OverlayStatusController
import RGStrings
import RGSwiftUI

private enum RGScreenshotError: Error { case unavailable, tooLarge }
private func rgRenderScreenshots(context: AccountContext, messages: [Message], data: PresentationData, width: CGFloat, avatars: [UIImage?]) -> Signal<UIImage, RGScreenshotError> {
    Signal { subscriber in
        let cancelled = Atomic(value: false)
        var cards: [UIImage] = [], area: CGFloat = 0
        func next(_ index: Int) {
            guard !cancelled.with({ $0 }) else { return }
            guard index < messages.count else {
                guard let image = rgMessageScreenshotStack(cards, backgroundColor: data.theme.chatList.backgroundColor) else { subscriber.putError(.tooLarge); return }
                subscriber.putNext(image); subscriber.putCompletion(); return
            }
            let message = messages[index]
            let item = context.sharedContext.makeChatMessagePreviewItem(context: context, messages: [message], theme: data.theme, strings: data.strings, wallpaper: data.chatWallpaper, fontSize: data.chatFontSize, chatBubbleCorners: data.chatBubbleCorners, dateTimeFormat: data.dateTimeFormat, nameOrder: data.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil, backgroundNode: nil, availableReactions: nil, accountPeer: nil, isCentered: false, isPreview: true, isStandalone: true, rank: nil, rankRole: nil, isGiftMessageComposerPreview: false)
            let params = ListViewItemLayoutParams(width: width, leftInset: 0, rightInset: 0, availableHeight: 12000, isStandalone: true)
            item.nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: true, neighbors: .none, completion: { node, apply in
                guard !cancelled.with({ $0 }) else { return }
                node.frame = CGRect(origin: .zero, size: CGSize(width: width, height: node.contentSize.height + node.insets.top + node.insets.bottom))
                apply().1(ListViewItemApply())
                node.recursivelyEnsureDisplaySynchronously(true)
                let source = (node as? ChatMessageItemView)?.getMessageContextSourceNode(stableId: message.stableId)
                let view = source?.contentNode.view ?? node.view
                let rect = source?.contentRect ?? view.bounds
                guard rect.width > 0, rect.height > 0 else { subscriber.putError(.unavailable); return }
                let size = CGSize(width: rect.width + 16, height: rect.height + 16)
                area += (max(260, size.width + 24) * (size.height + 74))
                guard area <= 6_000_000 else { subscriber.putError(.tooLarge); return }
                let format = UIGraphicsImageRendererFormat(); format.scale = min(2, UIScreen.main.scale); format.opaque = true
                let body = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                    data.theme.chatList.backgroundColor.setFill(); renderer.fill(CGRect(origin: .zero, size: size))
                    renderer.cgContext.translateBy(x: 8 - rect.minX, y: 8 - rect.minY); view.layer.render(in: renderer.cgContext)
                }
                let sender = message.author ?? message.peers[message.id.peerId]
                let name = sender.map { EnginePeer($0).displayTitle(strings: data.strings, displayOrder: data.nameDisplayOrder) } ?? "MessageScreenshot.UnknownSender".i18n(data.strings.rgLanguageCode)
                cards.append(rgMessageScreenshot(body: body, senderName: name, avatar: avatars[index], backgroundColor: data.theme.chatList.backgroundColor, textColor: data.theme.list.itemPrimaryTextColor))
                DispatchQueue.main.async { next(index + 1) }
            })
        }
        next(0)
        return ActionDisposable { _ = cancelled.swap(true) }
    }
}
public func rgExportMessageScreenshots(context: AccountContext, messages: [Message], controller: ViewController) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    func show(_ key: String) {
        controller.present(textAlertController(context: context, title: "MessageScreenshot.Action".i18n(data.strings.rgLanguageCode), text: key.i18n(data.strings.rgLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
    }
    guard !messages.isEmpty, messages.allSatisfy({ $0.id.peerId.namespace != Namespaces.Peer.SecretChat && !$0.containsSecretMedia && !$0.isCopyProtected() }) else { show("MessageScreenshot.Unavailable"); return }
    guard messages.count <= 30 else { show("MessageScreenshot.TooLarge"); return }
    let messages = messages.sorted { $0.index < $1.index }, request = MetaDisposable()
    let progress = OverlayStatusController(style: data.theme.overallDarkAppearance ? .dark : .light, type: .loading(cancelled: { request.dispose() }))
    controller.present(progress, in: .window(.root))
    let avatars = messages.map { message -> Signal<UIImage?, NoError> in
        guard let sender = message.author ?? message.peers[message.id.peerId] else { return .single(nil) }
        return peerAvatarCompleteImage(account: context.account, peer: EnginePeer(sender), size: CGSize(width: 76, height: 76)) |> filter { $0 != nil } |> take(1) |> timeout(2, queue: .mainQueue(), alternate: .single(nil))
    }
    let width = min(500, max(280, controller.view.bounds.width))
    request.set((combineLatest(queue: .mainQueue(), avatars) |> castError(RGScreenshotError.self) |> mapToSignal { rgRenderScreenshots(context: context, messages: messages, data: data, width: width, avatars: $0) } |> deliverOnMainQueue).start(next: { [weak controller] image in
        request.set(nil)
        progress.dismiss(completion: {
            guard let controller, var presenter = controller.view.window?.rootViewController else { return }
            while let presented = presenter.presentedViewController { presenter = presented }
            let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = presenter.view
            share.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            presenter.present(share, animated: true)
        })
    }, error: { error in
        request.set(nil); progress.dismiss(completion: { show(error == .tooLarge ? "MessageScreenshot.TooLarge" : "MessageScreenshot.Unavailable") })
    }))
}

// MARK: Regram
import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import LocalizedPeerData
import RGStrings

/// A separate, paginated page of one sender's messages in the originating chat/topic.
final class RGAuthorMessagesController: ViewController {
    private let context: AccountContext
    private let author: EnginePeer
    private let location: SearchMessagesLocation
    private var presentationData: PresentationData
    private let requestDisposable = MetaDisposable()
    private var presentationDisposable: Disposable?
    private var resultsNode: ChatSearchResultsControllerNode?
    private var currentResult: SearchMessagesResult?
    private var validLayout: (ContainerViewLayout, CGFloat)?
    private let emptyNode = ImmediateTextNode()
    private var emptyTextKey: String?
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    init(context: AccountContext, chatPeerId: EnginePeer.Id, threadId: Int64?, author: EnginePeer) {
        self.context = context
        self.author = author
        self.location = .peer(peerId: chatPeerId, fromId: author.id, tags: nil, reactions: nil, threadId: threadId, minDate: nil, maxDate: nil)
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings, style: .glass))
        self._hasGlassStyle = true
        self.title = "AuthorMessages.Title".i18n(self.presentationData.strings.baseLanguageCode, args: author.compactDisplayTitle)
        self.emptyNode.maximumNumberOfLines = 0
        self.emptyNode.textAlignment = .center
        self.emptyNode.displaysAsynchronously = false
        self.retryButton.addTarget(self, action: #selector(self.retryPressed), for: .touchUpInside)
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.presentationData = data
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationTheme: data.theme, presentationStrings: data.strings, style: .glass), transition: .immediate)
            if self.isNodeLoaded { self.updateTheme() }
        })
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.requestDisposable.dispose()
        self.presentationDisposable?.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.addSubnode(self.emptyNode)
        self.displayNode.view.addSubview(self.activityIndicator)
        self.displayNode.view.addSubview(self.retryButton)
        self.retryButton.isHidden = true
        self.displayNodeDidLoad()
        self.updateTheme()
        self.loadMessages()
    }

    private func updateTheme() {
        self.displayNode.backgroundColor = self.presentationData.theme.chatList.backgroundColor
        self.displayNode.view.overrideUserInterfaceStyle = self.presentationData.theme.overallDarkAppearance ? .dark : .light
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.activityIndicator.color = self.presentationData.theme.list.itemAccentColor
        self.retryButton.tintColor = self.presentationData.theme.list.itemAccentColor
        self.retryButton.titleLabel?.font = Font.regular(self.presentationData.listsFontSize.baseDisplaySize)
        self.retryButton.setTitle("AuthorMessages.Retry".i18n(self.presentationData.strings.baseLanguageCode), for: .normal)
        if let result = self.currentResult {
            self.updateTitle(result)
        } else {
            self.title = "AuthorMessages.Title".i18n(self.presentationData.strings.baseLanguageCode, args: self.author.compactDisplayTitle)
        }
        if let key = self.emptyTextKey { self.setEmptyText(key) }
    }

    @objc private func retryPressed() { self.loadMessages() }

    private func loadMessages() {
        self.emptyTextKey = nil
        self.emptyNode.isHidden = true
        self.retryButton.isHidden = true
        self.activityIndicator.startAnimating()
        let signal = self.context.engine.messages.searchMessages(location: self.location, query: "", state: nil, limit: 50)
        |> map { result, state -> (SearchMessagesResult, SearchMessagesState)? in (result, state) }
        |> timeout(25.0, queue: .mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        self.requestDisposable.set(signal.start(next: { [weak self] value in
            guard let self else { return }
            self.activityIndicator.stopAnimating()
            guard let (result, state) = value else {
                self.setEmptyText("AuthorMessages.LoadFailed")
                self.retryButton.isHidden = false
                return
            }
            self.currentResult = result
            self.updateTitle(result)
            guard !result.messages.isEmpty else { self.setEmptyText("AuthorMessages.Empty"); return }
            let node = ChatSearchResultsControllerNode(context: self.context, location: self.location, searchQuery: "", searchResult: result, searchState: state, presentInGlobalOverlay: { [weak self] controller in
                self?.presentInGlobalOverlay(controller)
            })
            node.resultsUpdated = { [weak self] result, _ in
                self?.currentResult = result
                self?.updateTitle(result)
            }
            node.resultSelected = { [weak self] index in self?.openMessage(at: index) }
            self.resultsNode?.removeFromSupernode()
            self.resultsNode = node
            // Keep the opaque results background below the navigation bar added by displayNodeDidLoad().
            self.displayNode.insertSubnode(node, at: 0)
            self.applyLayout()
        }))
    }

    private func updateTitle(_ result: SearchMessagesResult) {
        self.title = "AuthorMessages.Count".i18n(self.presentationData.strings.baseLanguageCode, args: self.author.compactDisplayTitle, String(result.totalCount))
    }

    private func setEmptyText(_ key: String) {
        self.emptyTextKey = key
        self.emptyNode.isHidden = false
        self.emptyNode.attributedText = NSAttributedString(string: key.i18n(self.presentationData.strings.baseLanguageCode), font: Font.regular(self.presentationData.listsFontSize.baseDisplaySize), textColor: self.presentationData.theme.list.itemSecondaryTextColor)
        self.applyLayout()
    }

    private func openMessage(at selectedIndex: Int) {
        guard let result = self.currentResult, let navigation = self.navigationController as? NavigationController else { return }
        let index: Int
        if case let .peer(peerId, _, _, _, _, _, _) = self.location, peerId.namespace == Namespaces.Peer.SecretChat {
            index = selectedIndex
        } else {
            index = result.messages.count - selectedIndex - 1
        }
        guard result.messages.indices.contains(index) else { return }
        let message = result.messages[index]
        guard let peer = message.peers[message.id.peerId].flatMap(EnginePeer.init) else { return }
        if case let .channel(channel) = peer, channel.isForumOrMonoForum, let threadId = message.threadId {
            let _ = self.context.sharedContext.navigateToForumThread(context: self.context, peerId: peer.id, threadId: threadId, messageId: message.id, navigationController: navigation, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).startStandalone()
        } else {
            self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigation, context: self.context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always, useExisting: false))
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = (layout, self.navigationLayout(layout: layout).navigationFrame.maxY)
        self.applyLayout()
    }

    private func applyLayout() {
        guard let (layout, navigationHeight) = self.validLayout else { return }
        self.resultsNode?.frame = CGRect(origin: .zero, size: layout.size)
        self.resultsNode?.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
        let centerY = navigationHeight + (layout.size.height - navigationHeight - layout.intrinsicInsets.bottom) * 0.5
        let textSize = self.emptyNode.updateLayout(CGSize(width: max(1.0, layout.size.width - 48.0), height: .greatestFiniteMagnitude))
        self.emptyNode.frame = CGRect(x: (layout.size.width - textSize.width) * 0.5, y: centerY - textSize.height * 0.5, width: textSize.width, height: textSize.height)
        let indicatorSize = self.activityIndicator.intrinsicContentSize
        self.activityIndicator.frame = CGRect(x: (layout.size.width - indicatorSize.width) * 0.5, y: centerY - indicatorSize.height * 0.5, width: indicatorSize.width, height: indicatorSize.height)
        self.retryButton.frame = CGRect(x: 24.0, y: centerY + textSize.height * 0.5 + 12.0, width: max(0.0, layout.size.width - 48.0), height: 44.0)
    }
}

// MARK: Regram — avatar context menus open the page without changing the chat search state.
extension ChatControllerImpl {
    func rgOpenAuthorMessages(_ author: EnginePeer) {
        guard let chatPeerId = self.chatLocation.peerId else { return }
        let threadId: Int64?
        if case let .replyThread(thread) = self.chatLocation { threadId = thread.threadId } else { threadId = nil }
        self.chatDisplayNode.dismissInput()
        self.push(RGAuthorMessagesController(context: self.context, chatPeerId: chatPeerId, threadId: threadId, author: author))
    }
}

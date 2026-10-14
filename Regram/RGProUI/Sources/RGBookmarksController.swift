// MARK: Regram
import Foundation
import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display
import LocalizedPeerData
import TelegramCore
import Postbox
import SwiftSignalKit
import UndoUI

private func rgBookmarkId(_ id: MessageId) -> RGBookmarkMessageId {
    RGBookmarkMessageId(peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id)
}

private func rgMessageId(_ id: RGBookmarkMessageId) -> MessageId {
    MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id)
}

private struct RGBookmarkRow: Identifiable {
    var id: RGBookmarkMessageId { bookmark.id }
    let bookmark: RGMessageBookmark
    let message: Message?
    let peer: EnginePeer?
}

private final class RGBookmarkList: ObservableObject {
    @Published var rows: [RGBookmarkRow] = []
    @Published var tags: [String] = []
    @Published var loading = false
    @Published var hasMore = false
    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var observer: NSObjectProtocol?
    private var generation = UUID()
    private var limit = 100
    @Published var selectedTag: String?
    init(context: AccountContext) {
        self.context = context
        observer = NotificationCenter.default.addObserver(forName: RGMessageBookmarks.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, let account = notification.object as? Int64, account == self.context.account.peerId.toInt64() else { return }
            self.reload()
        }
    }
    deinit { disposable.dispose(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    func select(_ tag: String?) { selectedTag = tag; limit = 100; reload() }
    func loadMore() { limit += 100; reload() }
    func reload() {
        let bookmarks = RGMessageBookmarks.shared.bookmarks(accountId: context.account.peerId.toInt64())
        var unique = Set<String>()
        tags = bookmarks.flatMap(\.tags).filter { unique.insert($0.lowercased()).inserted }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if let selectedTag, selectedTag != "", !tags.contains(where: { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) { self.selectedTag = nil }
        let filtered = bookmarks.filter { bookmark in
            guard let selectedTag = self.selectedTag else { return true }
            return selectedTag.isEmpty ? bookmark.tags.isEmpty : bookmark.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
        }
        hasMore = filtered.count > limit
        let visible = Array(filtered.prefix(limit))
        let id = UUID(); generation = id; loading = true
        disposable.set((context.account.postbox.transaction { transaction -> [RGBookmarkRow] in
            visible.map { bookmark in
                RGBookmarkRow(bookmark: bookmark, message: transaction.getMessage(rgMessageId(bookmark.id)), peer: transaction.getPeer(PeerId(bookmark.id.peerId)).map(EnginePeer.init))
            }
        } |> deliverOnMainQueue).start(next: { [weak self] values in
            guard let self, self.generation == id else { return }
            self.rows = values; self.loading = false
        }))
    }
}

private struct RGBookmarksView: View {
    @Environment(\.lang) private var lang
    @ObservedObject var list: RGBookmarkList
    let context: AccountContext
    let open: (RGBookmarkRow) -> Void
    let edit: (RGMessageBookmark) -> Void
    var body: some View {
        List {
            Section(footer: Text("Bookmarks.Notice".i18n(lang))) {
                Menu {
                    Button("Bookmarks.All".i18n(lang)) { list.select(nil) }
                    Button("Bookmarks.Untagged".i18n(lang)) { list.select("") }
                    ForEach(list.tags, id: \.self) { tag in Button(tag) { list.select(tag) } }
                } label: {
                    HStack { Text("Bookmarks.Filter".i18n(lang)); Spacer(); Text(list.selectedTag.map { $0.isEmpty ? "Bookmarks.Untagged".i18n(lang) : $0 } ?? "Bookmarks.All".i18n(lang)).foregroundColor(.secondary) }
                }.rgSettingsLink("tags")
            }
            if list.rows.isEmpty && !list.loading { Text("Bookmarks.Empty".i18n(lang)).foregroundColor(.secondary) }
            ForEach(list.rows) { row in
                Button { open(row) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let peer = row.peer {
                            let data = context.sharedContext.currentPresentationData.with { $0 }
                            Text(peer.rgGroupDisplayTitle(accountId: context.account.peerId.toInt64(), strings: data.strings, displayOrder: data.nameDisplayOrder)).font(.headline)
                        }
                        Text(row.message.map { $0.text.isEmpty ? "Bookmarks.Media".i18n(lang) : $0.text } ?? "Bookmarks.Unavailable".i18n(lang)).lineLimit(3)
                        if !row.bookmark.tags.isEmpty { Text(row.bookmark.tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundColor(.accentColor) }
                        Text(Date(timeIntervalSince1970: row.bookmark.addedAt), style: .date).font(.caption).foregroundColor(.secondary)
                    }.foregroundColor(.primary).padding(.vertical, 4)
                }.contextMenu {
                    Button("Bookmarks.EditTags".i18n(lang)) { edit(row.bookmark) }
                    Button("Bookmarks.Remove".i18n(lang), role: .destructive) { RGMessageBookmarks.shared.remove(accountId: context.account.peerId.toInt64(), messageId: row.id) }
                }
            }
            if list.loading { ProgressView() }
            else if list.hasMore { Button("Bookmarks.LoadMore".i18n(lang)) { list.loadMore() } }
        }.onAppear { list.reload() }
    }
}

private struct RGBookmarkEditorView: View {
    @Environment(\.lang) private var lang
    let availableTags: [String]
    let save: ([String]) -> Void
    let remove: () -> Void
    @State var selectedTags: [String]
    @State private var newTag = ""
    private var choices: [String] {
        var seen = Set<String>()
        return (selectedTags + availableTags).filter { seen.insert($0.lowercased()).inserted }
    }
    var body: some View {
        List {
            Section(header: Text("Bookmarks.Tags".i18n(lang)), footer: Text("Bookmarks.TagsNotice".i18n(lang))) {
                ForEach(choices, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { selectedTags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } }
                        else if selectedTags.count < RGMessageBookmarks.maximumTags { selectedTags.append(tag) }
                    } label: {
                        HStack { Text(tag); Spacer(); if selectedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { Image(systemName: "checkmark") } }
                    }
                }
                TextField("Bookmarks.NewTag".i18n(lang), text: $newTag).disableAutocorrection(true)
                Button("Bookmarks.AddTag".i18n(lang)) {
                    selectedTags = RGMessageBookmarks.normalizedTags(selectedTags + [newTag]); newTag = ""
                }.disabled(RGMessageBookmarks.normalizedTags([newTag]).isEmpty || selectedTags.count >= RGMessageBookmarks.maximumTags)
            }
            Section {
                Button("Bookmarks.Save".i18n(lang)) { save(selectedTags) }
                Button("Bookmarks.Remove".i18n(lang), role: .destructive, action: remove)
            }
        }
    }
}

private func rgBookmarkEditorController(context: AccountContext, bookmark: RGMessageBookmark) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Bookmarks.EditTags".i18n(data.strings.rgLanguageCode)
    let accountId = context.account.peerId.toInt64()
    let knownTags = RGMessageBookmarks.shared.bookmarks(accountId: accountId).flatMap(\.tags)
    let finish: () -> Void = { [weak controller] in _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true) }
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGBookmarkEditorView(availableTags: knownTags, save: { tags in
            RGMessageBookmarks.shared.save(accountId: accountId, messageId: bookmark.id, threadId: bookmark.threadId, tags: tags); finish()
        }, remove: { RGMessageBookmarks.shared.remove(accountId: accountId, messageId: bookmark.id); finish() }, selectedTags: bookmark.tags)
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}

public func rgBookmarkMessageController(context: AccountContext, message: Message) -> ViewController? {
    guard message.id.peerId.namespace != Namespaces.Peer.SecretChat, message.id.namespace == Namespaces.Message.Cloud, !message.containsSecretMedia else { return nil }
    let accountId = context.account.peerId.toInt64(), id = rgBookmarkId(message.id)
    if RGMessageBookmarks.shared.bookmark(accountId: accountId, messageId: id) == nil {
        RGMessageBookmarks.shared.save(accountId: accountId, messageId: id, threadId: message.threadId, tags: [])
    }
    guard let bookmark = RGMessageBookmarks.shared.bookmark(accountId: accountId, messageId: id) else { return nil }
    return rgBookmarkEditorController(context: context, bookmark: bookmark)
}

func rgBookmarksController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Bookmarks.Title".i18n(data.strings.rgLanguageCode)
    let list = RGBookmarkList(context: context)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGBookmarksView(list: list, context: context, open: { [weak controller] row in
            guard let navigation = controller?.navigationController as? NavigationController else { return }
            guard let peer = row.peer else {
                let data = context.sharedContext.currentPresentationData.with { $0 }
                controller?.present(UndoOverlayController(presentationData: data, content: .info(title: nil, text: "Bookmarks.ChatUnavailable".i18n(data.strings.rgLanguageCode), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in false }), in: .current)
                return
            }
            let location: NavigateToChatControllerParams.Location
            if let threadId = row.bookmark.threadId {
                let isForum: Bool
                let isMonoforum: Bool
                if case let .channel(channel) = peer { isForum = channel.flags.contains(.isForum); isMonoforum = channel.flags.contains(.isMonoforum) } else { isForum = false; isMonoforum = false }
                location = .replyThread(ChatReplyThreadMessage(peerId: peer.id, threadId: threadId, channelMessageId: nil, isChannelPost: false, isForumPost: isForum, isMonoforumPost: isMonoforum, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false))
            } else { location = .peer(peer) }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigation, context: context, chatLocation: location, subject: .message(id: .id(rgMessageId(row.id)), highlight: nil, timecode: nil, setupReply: false)))
        }, edit: { [weak controller] bookmark in
            (controller?.navigationController as? NavigationController)?.pushViewController(rgBookmarkEditorController(context: context, bookmark: bookmark))
        })
    })
    controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("bookmarks", focus: focusSetting), ignoreSafeArea: true))
    return controller
}

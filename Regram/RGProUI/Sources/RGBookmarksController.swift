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
import TelegramPresentationData
import PresentationDataUtils
import AsyncDisplayKit

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

private final class RGBookmarkList {
    var rows: [RGBookmarkRow] = []
    var tags: [String] = []
    var loading = false
    var hasMore = false
    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var observer: NSObjectProtocol?
    private var generation = UUID()
    var didUpdate: (() -> Void)?
    private var limit = 100
    var selectedTag: String?
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
        didUpdate?()
        disposable.set((context.account.postbox.transaction { transaction -> [RGBookmarkRow] in
            visible.map { bookmark in
                RGBookmarkRow(bookmark: bookmark, message: transaction.getMessage(rgMessageId(bookmark.id)), peer: transaction.getPeer(PeerId(bookmark.id.peerId)).map(EnginePeer.init))
            }
        } |> deliverOnMainQueue).start(next: { [weak self] values in
            guard let self, self.generation == id else { return }
            self.rows = values; self.loading = false; self.didUpdate?()
        }))
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
        RGSettingsList {
            RGSettingsSection(header: Text("Bookmarks.Tags".i18n(lang)), footer: Text("Bookmarks.TagsNotice".i18n(lang))) {
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
            RGSettingsSection {
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

// MARK: Regram — native table navigation avoids the hosted SwiftUI List/button transition path.
private final class RGBookmarksNativeController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let list: RGBookmarkList
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let dateFormatter = DateFormatter()
    private let appearance = MetaDisposable()
    private let navigationRequest = MetaDisposable()
    private var opening = false
    private var data: PresentationData
    private var lang: String { data.strings.rgLanguageCode }
    init(context: AccountContext) {
        self.context = context; list = RGBookmarkList(context: context); data = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: data, glassStyle: .default))
        self._hasGlassStyle = true
        title = "Bookmarks.Title".i18n(lang)
        navigationItem.backBarButtonItem = UIBarButtonItem(title: data.strings.Common_Back, style: .plain, target: nil, action: nil)
        list.didUpdate = { [weak self] in self?.table.reloadData() }
        appearance.set((context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }; self.data = data; self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: data, glassStyle: .default), transition: .immediate); self.applyTheme(); self.table.reloadData()
        }))
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { appearance.dispose(); navigationRequest.dispose() }
    override func loadDisplayNode() {
        displayNode = ASDisplayNode(); displayNodeDidLoad()
        table.dataSource = self; table.delegate = self; table.contentInsetAdjustmentBehavior = .never; table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 80
        displayNode.view.addSubview(table); applyTheme(); list.reload()
    }
    private func applyTheme() {
        title = "Bookmarks.Title".i18n(lang)
        dateFormatter.locale = Locale(identifier: lang); dateFormatter.dateStyle = .short
        table.overrideUserInterfaceStyle = data.theme.overallDarkAppearance ? .dark : .light
        table.backgroundColor = data.theme.list.blocksBackgroundColor; table.separatorColor = data.theme.list.itemBlocksSeparatorColor; table.tintColor = data.theme.list.itemAccentColor
        table.indicatorStyle = data.theme.overallDarkAppearance ? .white : .black
        if isNodeLoaded { displayNode.backgroundColor = data.theme.list.blocksBackgroundColor }
        statusBar.statusBarStyle = data.theme.rootController.statusBarStyle.style
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top)))
        table.contentInset.bottom = layout.insets(options: []).bottom
    }
    func numberOfSections(in tableView: UITableView) -> Int { 3 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : section == 1 ? max(1, list.rows.count) : (list.loading || list.hasMore ? 1 : 0) }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 0 ? "Bookmarks.Notice".i18n(lang) : nil }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = data.theme.list.itemBlocksBackgroundColor; cell.textLabel?.textColor = data.theme.list.itemPrimaryTextColor; cell.detailTextLabel?.textColor = data.theme.list.itemSecondaryTextColor
        cell.textLabel?.font = Font.regular(data.listsFontSize.baseDisplaySize); cell.detailTextLabel?.font = Font.regular(max(12, data.listsFontSize.baseDisplaySize - 2)); cell.detailTextLabel?.numberOfLines = 4
        cell.textLabel?.numberOfLines = 2
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = data.theme.list.itemHighlightedBackgroundColor
        cell.selectedBackgroundView = selectedBackground
        if indexPath.section == 0 {
            cell.textLabel?.text = "Bookmarks.Filter".i18n(lang); cell.detailTextLabel?.text = list.selectedTag.map { $0.isEmpty ? "Bookmarks.Untagged".i18n(lang) : $0 } ?? "Bookmarks.All".i18n(lang); cell.accessoryType = .disclosureIndicator
        } else if indexPath.section == 1 {
            guard list.rows.indices.contains(indexPath.row) else { cell.textLabel?.text = (list.loading ? "Bookmarks.Loading" : "Bookmarks.Empty").i18n(lang); cell.textLabel?.textColor = data.theme.list.itemSecondaryTextColor; cell.selectionStyle = .none; return cell }
            let row = list.rows[indexPath.row]
            cell.textLabel?.text = row.peer?.rgGroupDisplayTitle(accountId: context.account.peerId.toInt64(), strings: data.strings, displayOrder: data.nameDisplayOrder) ?? "Bookmarks.Unavailable".i18n(lang)
            let preview = row.message.map { $0.text.isEmpty ? "Bookmarks.Media".i18n(lang) : $0.text } ?? "Bookmarks.Unavailable".i18n(lang)
            let metadata = dateFormatter.string(from: Date(timeIntervalSince1970: row.bookmark.addedAt)) + (row.bookmark.tags.isEmpty ? "" : " · " + row.bookmark.tags.map { "#" + $0 }.joined(separator: "  "))
            cell.detailTextLabel?.text = metadata + "\n" + preview
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.textLabel?.text = (list.loading ? "Bookmarks.Loading" : "Bookmarks.LoadMore").i18n(lang)
            cell.textLabel?.textColor = list.loading ? data.theme.list.itemSecondaryTextColor : data.theme.list.itemAccentColor
            cell.selectionStyle = list.loading ? .none : .default
        }
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let sheet = ActionSheetController(presentationData: data)
            let choices: [(String, String?)] = [("Bookmarks.All".i18n(lang), nil), ("Bookmarks.Untagged".i18n(lang), "")] + list.tags.map { ($0, Optional($0)) }
            sheet.setItemGroups([ActionSheetItemGroup(items: choices.map { title, tag in ActionSheetButtonItem(title: title, color: .accent, action: { [weak self, weak sheet] in sheet?.dismissAnimated(); self?.list.select(tag) }) }), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, action: { [weak sheet] in sheet?.dismissAnimated() })])])
            present(sheet, in: .window(.root))
        } else if indexPath.section == 1, list.rows.indices.contains(indexPath.row) { open(list.rows[indexPath.row]) }
        else if indexPath.section == 2, !list.loading { list.loadMore() }
    }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, list.rows.indices.contains(indexPath.row) else { return nil }
        let row = list.rows[indexPath.row]
        let removeAction = UIContextualAction(style: .destructive, title: "Bookmarks.Remove".i18n(lang), handler: { [weak self] _, _, finish in guard let self else { finish(false); return }; RGMessageBookmarks.shared.remove(accountId: self.context.account.peerId.toInt64(), messageId: row.id); finish(true) })
        removeAction.backgroundColor = rgSettingsSwipeActionColor(data.theme.list.itemDestructiveColor)
        let editAction = UIContextualAction(style: .normal, title: "Bookmarks.EditTags".i18n(lang), handler: { [weak self] _, _, finish in
            guard let self else { finish(false); return }; (self.navigationController as? NavigationController)?.pushViewController(rgBookmarkEditorController(context: self.context, bookmark: row.bookmark)); finish(true)
        })
        editAction.backgroundColor = rgSettingsSwipeActionColor(data.theme.list.itemAccentColor)
        return UISwipeActionsConfiguration(actions: [removeAction, editAction])
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); opening = false }
    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.textColor = data.theme.list.freeTextColor
        footer.textLabel?.font = Font.regular(max(13.0, data.listsFontSize.baseDisplaySize - 3.0))
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if indexPath.section == 0 {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
                guard let self else { return nil }
                return UIMenu(children: [UIAction(title: "Settings.Link.Copy".i18n(self.lang), image: UIImage(systemName: "link"), handler: { _ in
                    UIPasteboard.general.string = RGSettingsDestination(page: "bookmarks", item: "tags")?.url.absoluteString
                })])
            })
        }
        guard indexPath.section == 1, list.rows.indices.contains(indexPath.row) else { return nil }
        let bookmark = list.rows[indexPath.row].bookmark
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [UIAction(title: "Bookmarks.EditTags".i18n(self.lang), image: UIImage(systemName: "tag"), handler: { [weak self] _ in
                guard let self else { return }; (self.navigationController as? NavigationController)?.pushViewController(rgBookmarkEditorController(context: self.context, bookmark: bookmark))
            }), UIAction(title: "Bookmarks.Remove".i18n(self.lang), image: UIImage(systemName: "trash"), attributes: .destructive, handler: { [weak self] _ in
                guard let self else { return }; RGMessageBookmarks.shared.remove(accountId: self.context.account.peerId.toInt64(), messageId: bookmark.id)
            })])
        })
    }
    private func open(_ row: RGBookmarkRow) {
        guard !opening else { return }
        guard let navigation = navigationController as? NavigationController else { return }
        guard let peer = row.peer else { present(textAlertController(context: context, title: title, text: "Bookmarks.ChatUnavailable".i18n(lang), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root)); return }
        opening = true
        let messageId = rgMessageId(row.id)
        let navigate: (NavigateToChatControllerParams.Location) -> Void = { [weak self, weak navigation] location in
            DispatchQueue.main.async { guard let self, let navigation else { return }; self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigation, context: self.context, chatLocation: location, subject: .message(id: .id(messageId), highlight: nil, timecode: nil, setupReply: false), useExisting: false)) }
        }
        if let threadId = row.bookmark.threadId, case let .channel(channel) = peer, channel.flags.contains(.isForum) || channel.flags.contains(.isMonoforum), threadId > 0, threadId <= Int64(Int32.max) {
            navigationRequest.set((context.engine.messages.fetchChannelReplyThreadMessage(messageId: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(threadId)), atMessageId: messageId) |> deliverOnMainQueue).start(next: { thread in navigate(.replyThread(thread)) }, error: { _ in navigate(.peer(peer)) }))
        } else { navigate(.peer(peer)) }
    }
}
public func rgBookmarksController(context: AccountContext, focusSetting: String? = nil) -> ViewController { RGBookmarksNativeController(context: context) }

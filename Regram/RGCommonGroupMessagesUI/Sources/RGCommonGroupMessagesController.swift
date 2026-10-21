// MARK: Regram — one person's searchable messages in groups shared with the current account.
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
import RGSimpleSettings

// The app routes status-bar taps through ViewController; keep UIKit's table out of that arbitration.
private func rgConfigureCommonGroupTableNavigation(controller: ViewController, table: UITableView, backTitle: String) {
    controller.navigationItem.backBarButtonItem = UIBarButtonItem(title: backTitle, style: .plain, target: nil, action: nil)
    table.scrollsToTop = false
    controller.scrollToTop = { [weak table] in
        guard let table else { return }
        table.setContentOffset(CGPoint(x: table.contentOffset.x, y: -table.adjustedContentInset.top), animated: true)
    }
}

private final class GroupSearch {
    let peer: EnginePeer
    var status: RGCommonGroupSearchStatus
    var cursor: SearchMessagesState?
    init(peer: EnginePeer) { self.peer = peer; self.status = .init(peerId: peer.id.toInt64()) }
}

private func messageOrder(_ message: Message) -> RGCommonMessageOrder {
    .init(timestamp: message.timestamp, peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id)
}

public func rgCommonGroupMessagesController(context: AccountContext, author: EnginePeer) -> ViewController? {
    guard author.id.namespace == Namespaces.Peer.CloudUser, author.id != context.account.peerId else { return nil }
    return RGCommonGroupMessagesController(context: context, author: author)
}

private final class RGCommonGroupMessagesController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let author: EnginePeer
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    private var filtersDisposable: Disposable?
    private var backgroundObserver: NSObjectProtocol?
    private var groupsContext: GroupsInCommonContext?
    private let groupsDisposable = MetaDisposable()
    private var groupTimer: Foundation.Timer?
    private var requests: [Int64: MetaDisposable] = [:]
    private var generation = UUID()
    private var groups: [Int64: GroupSearch] = [:]
    private var messages: [MessageId: Message] = [:]
    private var messageGroups: [MessageId: Int64] = [:]
    private var rows: [Message] = []
    private var selectedGroup: Int64?
    private var groupsComplete = false
    private var groupsFailed = false
    private var previousGroupPageCount: Int?
    private var active = false
    private var pausedByUser = false
    private var visibleLimit = RGCommonGroupSearchPolicy.displayPageSize
    private let dateFormatter = DateFormatter()
    private var lang: String {
        RGLocalizationManager.shared.preferredLocale(primary: presentationData.strings.primaryComponent.languageCode, secondary: presentationData.strings.secondaryComponent?.languageCode)
    }
    private var busy: Bool { groupsContext != nil || !requests.isEmpty }
    private var failed: Bool { groupsFailed || groups.values.contains { ($0.status.peerId == selectedGroup || selectedGroup == nil) && $0.status.failed } }

    init(context: AccountContext, author: EnginePeer) {
        self.context = context; self.author = author
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings))
        rgConfigureCommonGroupTableNavigation(controller: self, table: self.table, backTitle: self.presentationData.strings.Common_Back)
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }; self.presentationData = data
            self.navigationItem.backBarButtonItem?.title = data.strings.Common_Back
            self.navigationBar?.updatePresentationData(.init(presentationTheme: data.theme, presentationStrings: data.strings), transition: .immediate)
            if self.isNodeLoaded { self.updateAppearance() }
        })
        self.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pausedByUser = true; self?.pause()
        }
        self.filtersDisposable = (rgContentFiltersDidChange() |> deliverOnMainQueue).start(next: { [weak self] _ in self?.reloadRows() })
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        presentationDisposable?.dispose(); filtersDisposable?.dispose(); groupsDisposable.dispose(); groupTimer?.invalidate()
        requests.values.forEach { $0.dispose() }
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
    }
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.table.dataSource = self; self.table.delegate = self; self.table.rowHeight = UITableView.automaticDimension
        self.table.contentInsetAdjustmentBehavior = .never
        self.table.estimatedRowHeight = 100
        self.displayNode.view.addSubview(table)
        self.displayNodeDidLoad(); self.updateAppearance()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); active = true
        if !pausedByUser { resume() }
    }
    override func viewWillDisappear(_ animated: Bool) { pause(); super.viewWillDisappear(animated) }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top)))
        table.contentInset.bottom = layout.insets(options: []).bottom
    }
    private func updateAppearance() {
        title = "CommonGroups.Title".i18n(lang, args: author.compactDisplayTitle)
        dateFormatter.locale = Locale(identifier: lang); dateFormatter.dateStyle = .short; dateFormatter.timeStyle = .short
        table.overrideUserInterfaceStyle = presentationData.theme.overallDarkAppearance ? .dark : .light
        table.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        displayNode.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        table.separatorColor = presentationData.theme.list.itemBlocksSeparatorColor
        table.tintColor = presentationData.theme.list.itemAccentColor
        statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        table.reloadData()
    }
    private func pause() {
        active = false; generation = UUID(); groupTimer?.invalidate(); groupTimer = nil
        groupsDisposable.set(nil); groupsContext = nil
        let current = requests; requests.removeAll()
        current.values.forEach { $0.dispose() }
        groups.values.forEach { $0.status.loading = false }
        if isNodeLoaded { table.reloadData() }
    }
    private func resume() {
        guard active, !pausedByUser else { return }
        if !groupsComplete && !groupsFailed { loadGroups() } else { scheduleMessages() }
    }
    private func loadGroups() {
        guard groupsContext == nil else { return }
        let token = generation
        let value = GroupsInCommonContext(account: context.account, peerId: author.id)
        groupsContext = value; previousGroupPageCount = nil
        groupsDisposable.set((value.state |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, self.generation == token, self.active else { return }
            for rendered in state.peers {
                guard let peer = rendered.peers[rendered.peerId] else { continue }
                let engine = EnginePeer(peer)
                let isGroup: Bool
                switch engine { case .legacyGroup: isGroup = true; case let .channel(channel): if case .group = channel.info { isGroup = true } else { isGroup = false }; default: isGroup = false }
                guard isGroup else { continue }
                let id = engine.id.toInt64()
                if self.groups[id] == nil { self.groups[id] = GroupSearch(peer: engine) }
            }
            switch state.dataState {
            case .loading:
                self.groupTimer?.invalidate()
                self.groupTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
                    guard let self, self.generation == token, self.active else { return }
                    self.groupsFailed = true; self.groupsDisposable.set(nil); self.groupsContext = nil; self.scheduleMessages()
                }
            case let .ready(canLoadMore):
                self.groupTimer?.invalidate(); self.groupTimer = nil
                if state.loadFailed {
                    self.groupsFailed = true; self.groupsContext = nil; self.groupsDisposable.set(nil)
                } else if canLoadMore {
                    if self.previousGroupPageCount == state.peers.count {
                        self.groupsFailed = true; self.groupsContext = nil; self.groupsDisposable.set(nil)
                    } else { self.previousGroupPageCount = state.peers.count; value.loadMore() }
                } else {
                    self.groupsComplete = true; self.groupsContext = nil; self.groupsDisposable.set(nil)
                }
                self.scheduleMessages()
            }
            self.reloadRows()
        }))
    }
    private func filteredMessages() -> [Message] {
        messages.values.filter { selectedGroup == nil || messageGroups[$0.id] == selectedGroup }.sorted { messageOrder($0) > messageOrder($1) }
    }
    private func scheduleMessages() {
        guard active, !pausedByUser else { reloadRows(); return }
        // Query cached/loaded groups even if fetching another common-group page failed.
        guard groupsComplete || groupsFailed else { reloadRows(); return }
        let next = RGCommonGroupSearchPolicy.nextGroups(groups.values.map(\.status), orders: filteredMessages().map(messageOrder), visibleLimit: visibleLimit, selectedGroup: selectedGroup)
        for id in next { if let group = groups[id] { loadMessages(group) } }
        reloadRows()
    }
    private func loadMessages(_ group: GroupSearch) {
        let id = group.peer.id.toInt64(), token = generation, oldCursor = group.cursor
        group.status.loading = true
        let request = MetaDisposable(); requests[id] = request
        let location = SearchMessagesLocation.peer(peerId: group.peer.id, fromId: author.id, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil)
        let signal = context.engine.messages.searchMessages(location: location, query: "", state: oldCursor, limit: Int32(RGCommonGroupSearchPolicy.pageSize))
        |> map { result, cursor -> (SearchMessagesResult, SearchMessagesState)? in (result, cursor) }
        |> timeout(25, queue: .mainQueue(), alternate: .single(nil)) |> deliverOnMainQueue
        request.set(signal.start(next: { [weak self, weak group] value in
            guard let self, let group, self.generation == token, self.active else { return }
            self.requests.removeValue(forKey: id)?.dispose(); group.status.loading = false
            if let (result, cursor) = value {
                if result.rgRequestFailed || (!result.completed && oldCursor == cursor) { group.status.failed = true }
                else {
                    group.cursor = cursor; group.status.loaded = true; group.status.hasMore = !result.completed
                    if let oldest = result.messages.map(messageOrder).min() { group.status.oldest = min(group.status.oldest ?? oldest, oldest) }
                    // The engine also includes the group's pre-migration history, with its original peer ID.
                    for message in result.messages where message.author?.id == self.author.id {
                        self.messages[message.id] = message
                        self.messageGroups[message.id] = id
                    }
                }
            } else { group.status.failed = true }
            // Avoid recursive synchronous pages if the engine answers from local state.
            DispatchQueue.main.async { [weak self] in guard let self, self.generation == token else { return }; self.scheduleMessages() }
            self.reloadRows()
        }))
    }
    private func reloadRows() {
        let filter = RGContentFilterState(accountPeerId: context.account.peerId)
        rows = filteredMessages().prefix(visibleLimit).filter { !filter.shouldHide(message: EngineMessage($0)) }
        if isNodeLoaded { table.reloadData() }
    }
    private var canLoadMore: Bool {
        filteredMessages().count > visibleLimit || groups.values.contains { (selectedGroup == nil || $0.status.peerId == selectedGroup) && $0.status.hasMore && !$0.status.failed }
    }
    func numberOfSections(in tableView: UITableView) -> Int { 3 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 2 }
        if section == 2 { return !busy && !pausedByUser && canLoadMore ? 1 : 0 }
        return max(1, rows.count)
    }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "CommonGroups.Scope".i18n(lang) }
        guard section == 1 else { return nil }
        let status = "CommonGroups.Loaded".i18n(lang, args: String(rows.count), String(groups.count))
        return failed ? status + "\n" + "CommonGroups.PartialFailure".i18n(lang) : status
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: indexPath.section == 0 ? .value1 : .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        cell.textLabel?.textColor = presentationData.theme.list.itemPrimaryTextColor
        cell.detailTextLabel?.textColor = presentationData.theme.list.itemSecondaryTextColor
        if indexPath.section == 0 {
            cell.textLabel?.textColor = presentationData.theme.list.itemAccentColor
            if indexPath.row == 0 {
                cell.textLabel?.text = "CommonGroups.Filter".i18n(lang)
                cell.detailTextLabel?.text = selectedGroup.flatMap { groups[$0]?.peer }.map { groupTitle($0) } ?? "CommonGroups.All".i18n(lang)
                cell.accessoryType = .disclosureIndicator
            } else { cell.textLabel?.text = (busy ? "CommonGroups.Cancel" : pausedByUser ? "CommonGroups.Continue" : failed ? "CommonGroups.Retry" : "CommonGroups.Refresh").i18n(lang) }
        } else if indexPath.section == 2 {
            cell.textLabel?.text = "CommonGroups.LoadMore".i18n(lang)
            cell.textLabel?.textColor = presentationData.theme.list.itemAccentColor
        } else if rows.indices.contains(indexPath.row) {
            let message = rows[indexPath.row]
            cell.textLabel?.text = messageGroups[message.id].flatMap { groups[$0] }.map { groupTitle($0.peer) } ?? "CommonGroups.Group".i18n(lang)
            let spoilers = message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap(\.entities).compactMap { entity -> Range<Int>? in
                if case .Spoiler = entity.type { return entity.range }; return nil
            }
            let body = message.text.isEmpty ? "CommonGroups.Media".i18n(lang) : RGCommonGroupPreview.text(message.text, spoilers: spoilers, reveal: RGSimpleSettings.shared.automaticallyRevealSpoilers)
            cell.detailTextLabel?.text = body + "\n" + dateFormatter.string(from: Date(timeIntervalSince1970: Double(message.timestamp)))
            cell.detailTextLabel?.numberOfLines = 4; cell.accessoryType = .disclosureIndicator
        } else {
            cell.textLabel?.text = (busy ? "CommonGroups.Loading" : failed ? "CommonGroups.Failed" : groups.isEmpty ? "CommonGroups.NoGroups" : "CommonGroups.Empty").i18n(lang)
            cell.textLabel?.textColor = presentationData.theme.list.itemSecondaryTextColor; cell.textLabel?.numberOfLines = 0; cell.selectionStyle = .none
        }
        return cell
    }
    private func groupTitle(_ peer: EnginePeer) -> String {
        peer.rgGroupDisplayTitle(accountId: context.account.peerId.toInt64(), strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row == 0 { openGroupPicker() }
            else if busy { pausedByUser = true; pause(); active = true }
            else {
                let continuing = pausedByUser
                pausedByUser = false; active = true
                if failed { groups.values.forEach { $0.status.failed = false }; if groupsFailed { groupsFailed = false; groupsComplete = false }; resume() }
                else if continuing { resume() }
                else { refresh() }
            }
        } else if indexPath.section == 2 { loadMore() }
        else if rows.indices.contains(indexPath.row) { openMessage(rows[indexPath.row]) }
    }
    private func refresh() {
        pause(); groups.removeAll(); messages.removeAll(); messageGroups.removeAll(); rows = []; groupsComplete = false; groupsFailed = false
        selectedGroup = nil; visibleLimit = RGCommonGroupSearchPolicy.displayPageSize; active = true; pausedByUser = false; resume()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard active, !busy, !pausedByUser, !rows.isEmpty, scrollView.isDragging || scrollView.isDecelerating,
              scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 250 else { return }
        loadMore()
    }
    private func loadMore() {
        guard active, !busy, !pausedByUser, canLoadMore else { return }
        visibleLimit += RGCommonGroupSearchPolicy.displayPageSize; scheduleMessages()
    }
    private func openGroupPicker() {
        guard !groups.isEmpty, let navigation = navigationController as? NavigationController else { return }
        let choices = groups.values.map { ($0.peer.id.toInt64(), groupTitle($0.peer)) }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        let picker = RGCommonGroupPicker(presentationData: presentationData, choices: [(nil, "CommonGroups.All".i18n(lang))] + choices.map { (Optional($0.0), $0.1) }, selected: selectedGroup, select: { [weak self] id in
            guard let self else { return }; self.selectedGroup = id; self.visibleLimit = RGCommonGroupSearchPolicy.displayPageSize; self.reloadRows()
        })
        navigation.pushViewController(picker)
    }
    private func openMessage(_ message: Message) {
        guard let navigation = navigationController as? NavigationController,
              let peer = message.peers[message.id.peerId].map(EnginePeer.init) else { return }
        if case let .channel(channel) = peer, channel.isForumOrMonoForum, let thread = message.threadId {
            let _ = context.sharedContext.navigateToForumThread(context: context, peerId: peer.id, threadId: thread, messageId: message.id, navigationController: navigation, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).startStandalone()
        } else {
            context.sharedContext.navigateToChatController(.init(navigationController: navigation, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: nil, timecode: nil, setupReply: false), keepStack: .always, useExisting: false))
        }
    }
}

private final class RGCommonGroupPicker: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let data: PresentationData
    private let choices: [(Int64?, String)]
    private let selected: Int64?
    private let select: (Int64?) -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    init(presentationData: PresentationData, choices: [(Int64?, String)], selected: Int64?, select: @escaping (Int64?) -> Void) {
        self.data = presentationData; self.choices = choices; self.selected = selected; self.select = select
        super.init(navigationBarPresentationData: .init(presentationTheme: data.theme, presentationStrings: data.strings))
        rgConfigureCommonGroupTableNavigation(controller: self, table: self.table, backTitle: data.strings.Common_Back)
        title = "CommonGroups.Filter".i18n(RGLocalizationManager.shared.preferredLocale(primary: data.strings.primaryComponent.languageCode, secondary: data.strings.secondaryComponent?.languageCode))
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadDisplayNode() {
        displayNode = ASDisplayNode(); displayNode.view.addSubview(table); displayNodeDidLoad()
        table.dataSource = self; table.delegate = self; table.backgroundColor = data.theme.list.blocksBackgroundColor
        table.contentInsetAdjustmentBehavior = .never
        table.overrideUserInterfaceStyle = data.theme.overallDarkAppearance ? .dark : .light
        table.separatorColor = data.theme.list.itemBlocksSeparatorColor; table.tintColor = data.theme.list.itemAccentColor
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top)))
        table.contentInset.bottom = layout.insets(options: []).bottom
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { choices.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.textLabel?.text = choices[indexPath.row].1
        cell.backgroundColor = data.theme.list.itemBlocksBackgroundColor; cell.textLabel?.textColor = data.theme.list.itemPrimaryTextColor
        cell.accessoryType = choices[indexPath.row].0 == selected ? .checkmark : .none; return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard choices.indices.contains(indexPath.row) else { return }; select(choices[indexPath.row].0)
        _ = (navigationController as? NavigationController)?.popViewController(animated: true)
    }
}

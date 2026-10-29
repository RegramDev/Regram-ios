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
    var peer: EnginePeer
    var status: RGCommonGroupSearchStatus
    var cursor: SearchMessagesState?
    init(peer: EnginePeer) { self.peer = peer; self.status = .init(peerId: peer.id.toInt64()) }
}

private func messageOrder(_ message: Message) -> RGCommonMessageOrder {
    .init(timestamp: message.timestamp, peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id)
}

private enum RGCommonGroupSection: Int, CaseIterable {
    case filter, messages, status
}

private enum RGCommonGroupItem: Hashable {
    case filter, message(MessageId), empty, status
}

private final class RGCommonGroupDataSource: UITableViewDiffableDataSource<RGCommonGroupSection, RGCommonGroupItem> {
    var headerTitle: ((Int) -> String?)?
    var footerTitle: ((Int) -> String?)?
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { headerTitle?(section) }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { footerTitle?(section) }
}

public func rgCommonGroupMessagesController(context: AccountContext, author: EnginePeer) -> ViewController? {
    guard author.id.namespace == Namespaces.Peer.CloudUser, author.id != context.account.peerId else { return nil }
    return RGCommonGroupMessagesController(context: context, author: author)
}

private final class RGCommonGroupMessagesController: ViewController, UITableViewDelegate {
    private let context: AccountContext
    private let author: EnginePeer
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let header = RGCommonGroupHeaderView()
    private let refreshControl = UIRefreshControl()
    private var dataSource: RGCommonGroupDataSource?
    private var rowUpdate: DispatchWorkItem?
    private var scheduledSearch: DispatchWorkItem?
    private var refreshAllRows = false
    private var changedMessages = Set<MessageId>()
    private var sortedMessages: [Message]?
    private var primaryActionKey: String?
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    private var filtersDisposable: Disposable?
    private var backgroundObserver: NSObjectProtocol?
    private var resourceObservers: [NSObjectProtocol] = []
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
    private let fullDateFormatter = DateFormatter()
    private var lang: String {
        RGLocalizationManager.shared.preferredLocale(primary: presentationData.strings.primaryComponent.languageCode, secondary: presentationData.strings.secondaryComponent?.languageCode)
    }
    private var requestLimit: Int { RGCommonGroupSearchPolicy.requestLimit(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermalState: ProcessInfo.processInfo.thermalState.rawValue) }
    private var cooling: Bool { requestLimit == 0 }
    private var busy: Bool { groupsContext != nil || !requests.isEmpty || scheduledSearch != nil }
    private var failed: Bool { groupsFailed || groups.values.contains { ($0.status.peerId == selectedGroup || selectedGroup == nil) && $0.status.failed } }

    init(context: AccountContext, author: EnginePeer) {
        self.context = context; self.author = author
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings, glassStyle: .default))
        self._hasGlassStyle = true
        rgConfigureCommonGroupTableNavigation(controller: self, table: self.table, backTitle: presentationData.strings.Common_Back)
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }; self.presentationData = data
            self.navigationItem.backBarButtonItem?.title = data.strings.Common_Back
            self.navigationBar?.updatePresentationData(.init(presentationTheme: data.theme, presentationStrings: data.strings, glassStyle: .default), transition: .immediate)
            if self.isNodeLoaded { self.updateAppearance() }
        })
        self.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pausedByUser = true; self?.pause()
        }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            self.resourceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.active else { return }
                // Cancel excess in-flight work immediately; keep rows and successful cursors.
                self.pause(); self.active = true; self.resume()
            })
        }
        self.filtersDisposable = (rgContentFiltersDidChange() |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.refreshAllRows = true; self?.reloadRows(); self?.enqueueSearch()
        })
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        presentationDisposable?.dispose(); filtersDisposable?.dispose(); groupsDisposable.dispose(); groupTimer?.invalidate()
        requests.values.forEach { $0.dispose() }
        rowUpdate?.cancel(); scheduledSearch?.cancel()
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
        resourceObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.table.delegate = self; self.table.rowHeight = UITableView.automaticDimension
        self.table.contentInsetAdjustmentBehavior = .never
        self.table.estimatedRowHeight = 100
        self.table.register(RGCommonGroupMessageCell.self, forCellReuseIdentifier: "message")
        self.table.register(RGCommonGroupStateCell.self, forCellReuseIdentifier: "state")
        self.dataSource = RGCommonGroupDataSource(tableView: table, cellProvider: { [weak self] table, indexPath, item in
            self?.cell(tableView: table, indexPath: indexPath, item: item)
        })
        self.dataSource?.headerTitle = { [weak self] section in self?.headerTitle(section) }
        self.dataSource?.footerTitle = { [weak self] section in self?.footerTitle(section) }
        self.refreshControl.addTarget(self, action: #selector(refreshPressed), for: .valueChanged)
        self.table.refreshControl = refreshControl
        self.table.tableHeaderView = header
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
        let previousWidth = table.bounds.width
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top)))
        table.contentInset.bottom = layout.insets(options: []).bottom
        updateHeader()
        if previousWidth != table.bounds.width { refreshAllRows = true; reloadRows() }
    }
    private func updateAppearance() {
        title = "CommonGroups.PageTitle".i18n(lang)
        dateFormatter.locale = Locale(identifier: lang); dateFormatter.dateStyle = .short; dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true
        fullDateFormatter.locale = dateFormatter.locale; fullDateFormatter.dateStyle = .medium; fullDateFormatter.timeStyle = .short
        table.overrideUserInterfaceStyle = presentationData.theme.overallDarkAppearance ? .dark : .light
        table.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        displayNode.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        table.separatorColor = presentationData.theme.list.itemBlocksSeparatorColor
        table.tintColor = presentationData.theme.list.itemAccentColor
        refreshControl.tintColor = presentationData.theme.list.itemAccentColor
        statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        primaryActionKey = nil; refreshAllRows = true; updateRows()
    }
    private func updateHeader() {
        let summary: String
        if cooling { summary = "CommonGroups.Cooling".i18n(lang) }
        else if groupsContext != nil { summary = "CommonGroups.LoadingGroups".i18n(lang) }
        else if busy { summary = "CommonGroups.SummaryLoading".i18n(lang, args: String(rows.count)) }
        else if pausedByUser { summary = "CommonGroups.SummaryPaused".i18n(lang, args: String(rows.count)) }
        else if failed { summary = "CommonGroups.SummaryFailed".i18n(lang, args: String(rows.count)) }
        else { summary = "CommonGroups.Loaded".i18n(lang, args: String(rows.count), String(groups.count)) }
        header.update(context: context, author: author, summary: summary, loading: busy, data: presentationData)
        let actionKey = busy ? "CommonGroups.Cancel" : pausedByUser ? "CommonGroups.Continue" : failed ? "CommonGroups.Retry" : "CommonGroups.Refresh"
        if primaryActionKey != actionKey {
            primaryActionKey = actionKey
            let symbol = busy ? "pause" : pausedByUser ? "play" : "arrow.clockwise"
            let button = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: #selector(primaryPressed))
            button.accessibilityLabel = actionKey.i18n(lang)
            navigationItem.rightBarButtonItem = button
        }
        navigationItem.rightBarButtonItem?.isEnabled = !cooling
        guard table.bounds.width > 0.0 else { return }
        let size = header.systemLayoutSizeFitting(CGSize(width: table.bounds.width, height: 0.0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: ceil(size.height))
        if header.frame != frame { header.frame = frame; table.tableHeaderView = header }
    }
    private func pause(endRefreshing: Bool = true) {
        active = false; generation = UUID(); groupTimer?.invalidate(); groupTimer = nil
        scheduledSearch?.cancel(); scheduledSearch = nil
        groupsDisposable.set(nil); groupsContext = nil
        let current = requests; requests.removeAll()
        current.values.forEach { $0.dispose() }
        groups.values.forEach { $0.status.loading = false }
        if isNodeLoaded {
            if endRefreshing { refreshControl.endRefreshing() }
            reloadRows()
        }
    }
    private func resume() {
        guard active, !pausedByUser, !cooling else { reloadRows(); return }
        if !groupsComplete && !groupsFailed { loadGroups() }
        enqueueSearch()
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
                if let group = self.groups[id] {
                    if group.peer != engine { group.peer = engine; self.refreshAllRows = true }
                } else { self.groups[id] = GroupSearch(peer: engine) }
            }
            switch state.dataState {
            case .loading:
                self.groupTimer?.invalidate()
                self.groupTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
                    guard let self, self.generation == token, self.active else { return }
                    self.groupsFailed = true; self.groupsDisposable.set(nil); self.groupsContext = nil; self.enqueueSearch()
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
            }
            self.enqueueSearch()
            self.reloadRows()
        }))
    }
    private func filteredMessages() -> [Message] {
        if sortedMessages == nil { sortedMessages = messages.values.sorted { messageOrder($0) > messageOrder($1) } }
        let filter = RGContentFilterState(accountPeerId: context.account.peerId)
        return (sortedMessages ?? []).filter {
            (selectedGroup == nil || messageGroups[$0.id] == selectedGroup) && !filter.shouldHide(message: EngineMessage($0))
        }
    }
    private func enqueueSearch() {
        guard active, !pausedByUser, !cooling, scheduledSearch == nil else { return }
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.scheduledSearch = nil; self.scheduleMessages()
        }
        scheduledSearch = work
        let delay = RGCommonGroupSearchPolicy.requestDelay(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermalState: ProcessInfo.processInfo.thermalState.rawValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func scheduleMessages() {
        guard active, !pausedByUser, !cooling else { reloadRows(); return }
        // Group discovery shares the budget, so results can arrive before its final page.
        let budget = max(0, requestLimit - (groupsContext == nil ? 0 : 1))
        let next = RGCommonGroupSearchPolicy.nextGroups(groups.values.map(\.status), orders: filteredMessages().map(messageOrder), visibleLimit: visibleLimit, selectedGroup: selectedGroup, concurrencyLimit: budget)
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
                    var updated = false
                    for message in result.messages where message.author?.id == self.author.id {
                        // Search pages include earlier results; their unchanged objects need no layout.
                        guard self.messages[message.id] !== message || self.messageGroups[message.id] != id else { continue }
                        self.messages[message.id] = message
                        self.messageGroups[message.id] = id
                        self.changedMessages.insert(message.id)
                        updated = true
                    }
                    if updated { self.sortedMessages = nil }
                }
            } else { group.status.failed = true }
            self.enqueueSearch()
            self.reloadRows()
        }))
    }
    private func reloadRows() {
        guard isNodeLoaded, rowUpdate == nil else { return }
        // Several peers can finish together; publish one snapshot and retain existing cells.
        let work = DispatchWorkItem { [weak self] in self?.updateRows() }
        rowUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func updateRows() {
        rowUpdate?.cancel(); rowUpdate = nil
        guard let dataSource else { return }
        rows = Array(filteredMessages().prefix(visibleLimit))
        updateHeader()
        if !busy { refreshControl.endRefreshing() }
        var snapshot = NSDiffableDataSourceSnapshot<RGCommonGroupSection, RGCommonGroupItem>()
        snapshot.appendSections(RGCommonGroupSection.allCases)
        snapshot.appendItems([.filter], toSection: .filter)
        snapshot.appendItems(rows.isEmpty ? [.empty] : rows.map { .message($0.id) }, toSection: .messages)
        if !rows.isEmpty { snapshot.appendItems([.status], toSection: .status) }
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        let updates = snapshot.itemIdentifiers.filter { item in
            guard existing.contains(item) else { return false }
            if refreshAllRows { return true }
            if case let .message(id) = item { return changedMessages.contains(id) }
            return true
        }
        snapshot.reconfigureItems(updates)
        refreshAllRows = false; changedMessages.removeAll()
        dataSource.apply(snapshot, animatingDifferences: false)
        // UIKit retains section headers when only items change.
        for section in RGCommonGroupSection.allCases {
            if let view = table.headerView(forSection: section.rawValue) {
                view.textLabel?.text = headerTitle(section.rawValue)
                styleSectionLabel(view, isHeader: true)
            }
            if let view = table.footerView(forSection: section.rawValue) {
                view.textLabel?.text = footerTitle(section.rawValue)
                styleSectionLabel(view, isHeader: false)
            }
        }
    }
    private var canLoadMore: Bool {
        filteredMessages().count > visibleLimit || groups.values.contains { (selectedGroup == nil || $0.status.peerId == selectedGroup) && $0.status.hasMore && !$0.status.failed }
    }
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        styleSectionLabel(view, isHeader: true)
    }
    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        styleSectionLabel(view, isHeader: false)
    }
    private func styleSectionLabel(_ view: UIView, isHeader: Bool) {
        guard let view = view as? UITableViewHeaderFooterView else { return }
        view.textLabel?.textColor = isHeader ? presentationData.theme.list.sectionHeaderTextColor : presentationData.theme.list.freeTextColor
        view.textLabel?.font = Font.regular(max(13.0, presentationData.listsFontSize.baseDisplaySize - 4.0))
        view.textLabel?.numberOfLines = 0
    }
    private func headerTitle(_ section: Int) -> String? {
        section == RGCommonGroupSection.messages.rawValue ? "CommonGroups.Results".i18n(lang, args: String(rows.count)) : nil
    }
    private func footerTitle(_ section: Int) -> String? {
        let scopeSection = rows.isEmpty ? RGCommonGroupSection.messages : .status
        return section == scopeSection.rawValue ? "CommonGroups.Scope".i18n(lang) : nil
    }
    private func cell(tableView: UITableView, indexPath: IndexPath, item: RGCommonGroupItem) -> UITableViewCell {
        if item == .filter {
            let cell = tableView.dequeueReusableCell(withIdentifier: "filter") ?? UITableViewCell(style: .value1, reuseIdentifier: "filter")
            cell.textLabel?.text = "CommonGroups.Filter".i18n(lang)
            cell.detailTextLabel?.text = selectedGroup.flatMap { groups[$0]?.peer }.map { groupTitle($0) } ?? "CommonGroups.All".i18n(lang)
            cell.textLabel?.font = Font.regular(presentationData.listsFontSize.baseDisplaySize)
            cell.detailTextLabel?.font = Font.regular(presentationData.listsFontSize.baseDisplaySize)
            cell.textLabel?.textColor = presentationData.theme.list.itemPrimaryTextColor
            cell.detailTextLabel?.textColor = presentationData.theme.list.itemSecondaryTextColor
            cell.backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = groups.isEmpty ? .none : .default
            cell.contentView.alpha = groups.isEmpty ? 0.5 : 1.0
            let selection = cell.selectedBackgroundView ?? UIView()
            selection.backgroundColor = presentationData.theme.list.itemHighlightedBackgroundColor
            cell.selectedBackgroundView = selection
            cell.accessibilityTraits = groups.isEmpty ? [.button, .notEnabled] : .button
            return cell
        }
        if case let .message(id) = item, let message = messages[id] {
            let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath) as! RGCommonGroupMessageCell
            let group = messageGroups[message.id].flatMap { groups[$0]?.peer }
            // Rich previews mask their own spoilers; legacy entity offsets belong to message.text.
            let spoilers: [Range<Int>] = message.attributes.contains(where: { $0 is RichTextMessageAttribute }) ? [] : message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap(\.entities).compactMap { entity -> Range<Int>? in
                if case .Spoiler = entity.type { return entity.range }; return nil
            }
            let preview = RGSimpleSettings.shared.automaticallyRevealSpoilers ? message.rgTextContent : message.rgPreviewText
            let body = preview.isEmpty ? "CommonGroups.Media".i18n(lang) : RGCommonGroupPreview.text(preview, spoilers: spoilers, reveal: RGSimpleSettings.shared.automaticallyRevealSpoilers)
            let date = Date(timeIntervalSince1970: Double(message.timestamp))
            cell.update(context: context, group: group, title: group.map { groupTitle($0) } ?? "CommonGroups.Group".i18n(lang), date: dateFormatter.string(from: date), fullDate: fullDateFormatter.string(from: date), body: body, openHint: "CommonGroups.OpenMessage".i18n(lang), availableWidth: tableView.bounds.width, data: presentationData)
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "state", for: indexPath) as! RGCommonGroupStateCell
        let isLoading = !cooling && (busy || (active && !groupsComplete && !groupsFailed && !pausedByUser))
        let titleKey: String
        let detailKey: String?
        let symbol: String
        let actionable: Bool
        if cooling {
            titleKey = "CommonGroups.Cooling"; detailKey = "CommonGroups.Paused"; symbol = "thermometer"; actionable = false
        } else if isLoading {
            titleKey = groupsContext != nil || groups.isEmpty ? "CommonGroups.LoadingGroups" : "CommonGroups.Loading"
            detailKey = nil; symbol = "magnifyingglass"; actionable = false
        } else if pausedByUser {
            titleKey = "CommonGroups.Continue"; detailKey = "CommonGroups.Paused"; symbol = "pause.circle"; actionable = true
        } else if failed {
            titleKey = "CommonGroups.Retry"; detailKey = "CommonGroups.PartialFailure"; symbol = "exclamationmark.circle"; actionable = true
        } else if item == .status {
            titleKey = canLoadMore ? "CommonGroups.LoadMore" : "CommonGroups.AllLoaded"
            detailKey = nil; symbol = canLoadMore ? "arrow.down.circle" : "checkmark.circle"; actionable = canLoadMore
        } else {
            titleKey = groups.isEmpty ? "CommonGroups.NoGroups" : "CommonGroups.Empty"
            detailKey = groups.isEmpty ? nil : "CommonGroups.EmptyHint"; symbol = groups.isEmpty ? "person.2" : "text.bubble"; actionable = false
        }
        cell.update(title: titleKey.i18n(lang), detail: detailKey?.i18n(lang), symbol: symbol, loading: isLoading, actionable: actionable, compact: item == .status, data: presentationData)
        return cell
    }
    private func groupTitle(_ peer: EnginePeer) -> String {
        peer.rgGroupDisplayTitle(accountId: context.account.peerId.toInt64(), strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .filter: openGroupPicker()
        case let .message(id): if let message = messages[id] { openMessage(message) }
        case .empty, .status:
            if !busy && !cooling && (pausedByUser || failed) { performPrimaryAction() }
            else if item == .status { loadMore() }
        }
    }
    @objc private func primaryPressed() { performPrimaryAction() }
    @objc private func refreshPressed() {
        guard !cooling else { refreshControl.endRefreshing(); return }
        refresh()
    }
    private func performPrimaryAction() {
        if busy { pausedByUser = true; pause(); active = true; return }
        let continuing = pausedByUser
        pausedByUser = false; active = true
        if failed { groups.values.forEach { $0.status.failed = false }; if groupsFailed { groupsFailed = false; groupsComplete = false }; resume() }
        else if continuing { resume() }
        else { refresh() }
    }
    private func refresh() {
        pause(endRefreshing: false); groups.removeAll(); messages.removeAll(); messageGroups.removeAll(); sortedMessages = nil; changedMessages.removeAll(); groupsComplete = false; groupsFailed = false
        selectedGroup = nil; visibleLimit = RGCommonGroupSearchPolicy.displayPageSize; active = true; pausedByUser = false; resume()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard active, !busy, !pausedByUser, !rows.isEmpty, scrollView.isDragging || scrollView.isDecelerating,
              scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 250 else { return }
        loadMore()
    }
    private func loadMore() {
        guard active, !busy, !pausedByUser, !cooling, canLoadMore else { return }
        visibleLimit += RGCommonGroupSearchPolicy.displayPageSize; enqueueSearch(); reloadRows()
    }
    private func openGroupPicker() {
        guard !groups.isEmpty, let navigation = navigationController as? NavigationController else { return }
        let choices = groups.values.map(\.peer).sorted { groupTitle($0).localizedStandardCompare(groupTitle($1)) == .orderedAscending }
        let picker = RGCommonGroupPicker(context: context, choices: choices, selected: selectedGroup, select: { [weak self] id in
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
            context.sharedContext.navigateToChatController(.init(navigationController: navigation, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always, useExisting: false))
        }
    }
}

private final class RGCommonGroupPicker: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var data: PresentationData
    private var presentationDisposable: Disposable?
    private let choices: [EnginePeer]
    private let selected: Int64?
    private let select: (Int64?) -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var lang: String { RGLocalizationManager.shared.preferredLocale(primary: data.strings.primaryComponent.languageCode, secondary: data.strings.secondaryComponent?.languageCode) }
    init(context: AccountContext, choices: [EnginePeer], selected: Int64?, select: @escaping (Int64?) -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.context = context; self.data = presentationData
        self.choices = choices; self.selected = selected; self.select = select
        super.init(navigationBarPresentationData: .init(presentationTheme: presentationData.theme, presentationStrings: presentationData.strings, glassStyle: .default))
        self._hasGlassStyle = true
        rgConfigureCommonGroupTableNavigation(controller: self, table: self.table, backTitle: presentationData.strings.Common_Back)
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.data = data
            self.navigationItem.backBarButtonItem?.title = data.strings.Common_Back
            self.navigationBar?.updatePresentationData(.init(presentationTheme: data.theme, presentationStrings: data.strings, glassStyle: .default), transition: .immediate)
            if self.isNodeLoaded { self.updateAppearance() }
        })
        title = "CommonGroups.Filter".i18n(lang)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { presentationDisposable?.dispose() }
    override func loadDisplayNode() {
        displayNode = ASDisplayNode(); displayNode.view.addSubview(table); displayNodeDidLoad()
        table.dataSource = self; table.delegate = self
        table.contentInsetAdjustmentBehavior = .never
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 72.0
        table.register(RGCommonGroupPeerCell.self, forCellReuseIdentifier: "group")
        updateAppearance()
    }
    private func updateAppearance() {
        title = "CommonGroups.Filter".i18n(lang)
        table.overrideUserInterfaceStyle = data.theme.overallDarkAppearance ? .dark : .light
        table.backgroundColor = data.theme.list.blocksBackgroundColor
        table.separatorColor = data.theme.list.itemBlocksSeparatorColor
        table.tintColor = data.theme.list.itemAccentColor
        displayNode.backgroundColor = data.theme.list.blocksBackgroundColor
        statusBar.statusBarStyle = data.theme.rootController.statusBarStyle.style
        table.reloadData()
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top)))
        table.contentInset.bottom = layout.insets(options: []).bottom
    }
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : choices.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "CommonGroups.All".i18n(lang)
            cell.textLabel?.font = Font.regular(data.listsFontSize.baseDisplaySize)
            cell.textLabel?.textColor = data.theme.list.itemAccentColor
            cell.imageView?.image = UIImage(systemName: "square.stack.3d.up")
            cell.tintColor = data.theme.list.itemAccentColor
            cell.backgroundColor = data.theme.list.itemBlocksBackgroundColor
            let selection = UIView()
            selection.backgroundColor = data.theme.list.itemHighlightedBackgroundColor
            cell.selectedBackgroundView = selection
            cell.textLabel?.numberOfLines = 0
            cell.accessoryType = selected == nil ? .checkmark : .none
            cell.accessibilityTraits = selected == nil ? [.button, .selected] : .button
            return cell
        }
        let peer = choices[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "group", for: indexPath) as! RGCommonGroupPeerCell
        cell.update(context: context, peer: peer, title: peer.rgGroupDisplayTitle(accountId: context.account.peerId.toInt64(), strings: data.strings, displayOrder: data.nameDisplayOrder), summary: nil, data: data, selected: peer.id.toInt64() == selected)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 { select(nil) }
        else {
            guard choices.indices.contains(indexPath.row) else { return }
            select(choices[indexPath.row].id.toInt64())
        }
        _ = (navigationController as? NavigationController)?.popViewController(animated: true)
    }
}

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
    private let header = RGCommonGroupHeaderView()
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
    private let fullDateFormatter = DateFormatter()
    private var lang: String {
        RGLocalizationManager.shared.preferredLocale(primary: presentationData.strings.primaryComponent.languageCode, secondary: presentationData.strings.secondaryComponent?.languageCode)
    }
    private var busy: Bool { groupsContext != nil || !requests.isEmpty }
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
        self.table.register(RGCommonGroupMessageCell.self, forCellReuseIdentifier: "message")
        self.table.register(RGCommonGroupStateCell.self, forCellReuseIdentifier: "state")
        self.header.filterAction = { [weak self] in self?.openGroupPicker() }
        self.header.primaryAction = { [weak self] in self?.performPrimaryAction() }
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
        if previousWidth != table.bounds.width { table.reloadData() }
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
        statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        updateHeader()
        table.reloadData()
    }
    private func updateHeader() {
        let summary: String
        if groupsContext != nil { summary = "CommonGroups.LoadingGroups".i18n(lang) }
        else if busy { summary = "CommonGroups.SummaryLoading".i18n(lang, args: String(rows.count)) }
        else if pausedByUser { summary = "CommonGroups.SummaryPaused".i18n(lang, args: String(rows.count)) }
        else if failed { summary = "CommonGroups.SummaryFailed".i18n(lang, args: String(rows.count)) }
        else { summary = "CommonGroups.Loaded".i18n(lang, args: String(rows.count), String(groups.count)) }
        header.update(
            context: context, author: author, summary: summary,
            filterTitle: selectedGroup.flatMap { groups[$0]?.peer }.map { groupTitle($0) } ?? "CommonGroups.All".i18n(lang),
            filterHint: "CommonGroups.Filter".i18n(lang), filterEnabled: !groups.isEmpty,
            actionTitle: (busy ? "CommonGroups.Cancel" : pausedByUser ? "CommonGroups.Continue" : failed ? "CommonGroups.Retry" : "CommonGroups.Refresh").i18n(lang),
            actionSymbol: busy ? "pause.fill" : pausedByUser ? "play.fill" : "arrow.clockwise",
            loading: busy, data: presentationData
        )
        guard table.bounds.width > 0.0 else { return }
        let size = header.systemLayoutSizeFitting(CGSize(width: table.bounds.width, height: 0.0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: ceil(size.height))
        if header.frame != frame { header.frame = frame; table.tableHeaderView = header }
    }
    private func pause() {
        active = false; generation = UUID(); groupTimer?.invalidate(); groupTimer = nil
        groupsDisposable.set(nil); groupsContext = nil
        let current = requests; requests.removeAll()
        current.values.forEach { $0.dispose() }
        groups.values.forEach { $0.status.loading = false }
        if isNodeLoaded { updateHeader(); table.reloadData() }
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
        if isNodeLoaded { updateHeader(); table.reloadData() }
    }
    private var canLoadMore: Bool {
        filteredMessages().count > visibleLimit || groups.values.contains { (selectedGroup == nil || $0.status.peerId == selectedGroup) && $0.status.hasMore && !$0.status.failed }
    }
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(1, rows.count) : (rows.isEmpty ? 0 : 1)
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
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "CommonGroups.Results".i18n(lang, args: String(rows.count)) : nil
    }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 { return "CommonGroups.Scope".i18n(lang) }
        return failed && !rows.isEmpty ? "CommonGroups.PartialFailure".i18n(lang) : nil
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 && rows.indices.contains(indexPath.row) {
            let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath) as! RGCommonGroupMessageCell
            let message = rows[indexPath.row]
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
        let isLoading = busy || (!groupsComplete && !groupsFailed && !pausedByUser)
        let titleKey: String
        let detailKey: String?
        let symbol: String
        let actionable: Bool
        if isLoading {
            titleKey = groupsContext != nil || groups.isEmpty ? "CommonGroups.LoadingGroups" : "CommonGroups.Loading"
            detailKey = nil; symbol = "magnifyingglass"; actionable = false
        } else if pausedByUser {
            titleKey = "CommonGroups.Continue"; detailKey = "CommonGroups.Paused"; symbol = "pause.circle"; actionable = true
        } else if failed {
            titleKey = "CommonGroups.Retry"; detailKey = "CommonGroups.PartialFailure"; symbol = "exclamationmark.circle"; actionable = true
        } else if indexPath.section == 1 {
            titleKey = canLoadMore ? "CommonGroups.LoadMore" : "CommonGroups.AllLoaded"
            detailKey = nil; symbol = canLoadMore ? "arrow.down.circle" : "checkmark.circle"; actionable = canLoadMore
        } else {
            titleKey = groups.isEmpty ? "CommonGroups.NoGroups" : "CommonGroups.Empty"
            detailKey = groups.isEmpty ? nil : "CommonGroups.EmptyHint"; symbol = groups.isEmpty ? "person.2" : "text.bubble"; actionable = false
        }
        cell.update(title: titleKey.i18n(lang), detail: detailKey?.i18n(lang), symbol: symbol, loading: isLoading, actionable: actionable, compact: indexPath.section == 1, data: presentationData)
        return cell
    }
    private func groupTitle(_ peer: EnginePeer) -> String {
        peer.rgGroupDisplayTitle(accountId: context.account.peerId.toInt64(), strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 && rows.indices.contains(indexPath.row) { openMessage(rows[indexPath.row]) }
        else if !busy && (pausedByUser || failed) { performPrimaryAction() }
        else if indexPath.section == 1 { loadMore() }
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
            context.sharedContext.navigateToChatController(.init(navigationController: navigation, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: nil, timecode: nil, setupReply: false), keepStack: .always, useExisting: false))
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

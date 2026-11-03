import Foundation
import SwiftSignalKit

// External engine and UI adapters only; the runner compiles the production controller intact.
enum EnginePeer: Equatable {
    struct Id: Hashable {
        let value: Int64
        init(_ value: Int64) { self.value = value }
        func toInt64() -> Int64 { value }
        var id: Id { self }
        func _internalGetInt64Value() -> Int64 { value }
    }
    case user(TelegramUser), legacyGroup(TestGroup), channel(TestChannel)
    var id: Id {
        switch self { case let .user(peer): return peer.id; case let .legacyGroup(peer): return peer.id; case let .channel(peer): return peer.id }
    }
    var compactDisplayTitle: String {
        switch self { case let .user(peer): return peer.title; case let .legacyGroup(peer): return peer.title; case let .channel(peer): return peer.title }
    }
}
struct TestGroup: Equatable { let id: EnginePeer.Id; let title: String }
struct TestChannel: Equatable {
    enum Info: Equatable { case group, broadcast }
    let id: EnginePeer.Id; let title: String; let info: Info
}
struct TelegramUser: Equatable {
    let id: EnginePeer.Id
    let title: String
    init(id: EnginePeer.Id, accessHash: Int?, firstName: String?, lastName: String?, username: String?, phone: String?, photo: [Int], botInfo: Int?, restrictionInfo: Int?, flags: Set<Int>, emojiStatus: Int?, usernames: [String], storiesHidden: Bool?, nameColor: Int?, backgroundEmojiId: Int?, profileColor: Int?, profileBackgroundEmojiId: Int?, subscriberCount: Int?, verificationIconFileId: Int?) {
        self.id = id; self.title = firstName ?? ""
    }
}
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: EnginePeer.Id } } } } }
typealias PeerRequest = TelegramEngine.EngineData.Item.Peer.Peer
struct EngineDataMap { let items: [PeerRequest]; init(_ items: [PeerRequest]) { self.items = items } }
final class TestData {
    var peers: [EnginePeer.Id: EnginePeer] = [:]
    var deferResponses = false
    var pendingResponses: [() -> Void] = []
    func get(_ request: PeerRequest) -> Signal<EnginePeer?, NoError> { .single(peers[request.id]) }
    func get(_ request: EngineDataMap) -> Signal<[EnginePeer.Id: EnginePeer?], NoError> {
        let value: [EnginePeer.Id: EnginePeer?] = Dictionary(uniqueKeysWithValues: request.items.map { ($0.id, peers[$0.id]) })
        if !deferResponses { return .single(value) }
        return Signal { subscriber in
            self.pendingResponses.append { subscriber.putNext(value); subscriber.putCompletion() }
            return EmptyDisposable
        }
    }
    func completeResponses() {
        let responses = pendingResponses; pendingResponses.removeAll()
        for response in responses { response() }
    }
}
final class TestEngine { let data = TestData() }
struct TestStrings { let rgLanguageCode = "en"; let Common_Back = "Back" }
struct TestPresentationData { let strings = TestStrings(); let nameDisplayOrder = "firstLast" }
struct TestAtomic<T> { let value: T; func with<R>(_ f: (T) -> R) -> R { f(value) } }
struct TestAccount { let peerId: EnginePeer.Id }
final class AccountContext {
    let account: TestAccount
    let engine = TestEngine()
    let sharedContext = TestSharedContext()
    init(_ accountId: Int64) { account = TestAccount(peerId: EnginePeer.Id(accountId)) }
}
struct ChatListNodePeersFilter: OptionSet {
    let rawValue: Int
    static let onlyGroups = Self(rawValue: 1)
    static let excludeRecent = Self(rawValue: 2)
    static let doNotSearchMessages = Self(rawValue: 4)
    static let removeSearchHeader = Self(rawValue: 8)
}
struct PeerSelectionControllerParams {
    let context: AccountContext
    let filter: ChatListNodePeersFilter
    var hasContactSelector = true
    let title: String?
}
enum ChannelMembersSearchControllerMode { case select }
enum ChannelMembersSearchFilter { case excludeNonMembers, exclude([EnginePeer.Id]) }
struct RenderedChannelParticipant { }
struct ChannelMembersSearchControllerParams {
    let context: AccountContext; let peerId: EnginePeer.Id
    let mode: ChannelMembersSearchControllerMode; let filters: [ChannelMembersSearchFilter]
    let openPeer: (EnginePeer, RenderedChannelParticipant?) -> Void
}
enum TestPeerInfoMode { case generic }
final class TestSharedContext {
    let presentationData: Signal<TestPresentationData, NoError> = .single(TestPresentationData())
    let currentPresentationData = TestAtomic(value: TestPresentationData())
    weak var lastGroupPicker: PeerSelectionController?
    weak var lastMemberPicker: ChannelMembersSearchController?
    func makePeerSelectionController(_ params: PeerSelectionControllerParams) -> PeerSelectionController {
        let picker = PeerSelectionController(params); lastGroupPicker = picker; return picker
    }
    func makeChannelMembersSearchController(params: ChannelMembersSearchControllerParams) -> ChannelMembersSearchController {
        let picker = ChannelMembersSearchController(params); lastMemberPicker = picker; return picker
    }
    func makePeerInfoController(context: AccountContext, updatedPresentationData: Any?, peer: EnginePeer, mode: TestPeerInfoMode, avatarInitiallyExpanded: Bool, fromChat: Bool, requestsContext: Any?) -> ViewController? { ViewController() }
}
enum TestPresentationContext { enum Level { case root }; case window(Level) }
class ViewController {
    weak var navigationController: AnyObject?
    var presented: [ViewController] = []
    func present(_ controller: ViewController, in context: TestPresentationContext) { presented.append(controller) }
    func appeared() { }
    func dismiss() { (navigationController as? NavigationController)?.remove(self) }
    func replace(with controller: ViewController) { (navigationController as? NavigationController)?.replace(self, with: controller) }
}
final class NavigationController {
    var viewControllers: [ViewController] = []
    func pushViewController(_ controller: ViewController) {
        controller.navigationController = self; viewControllers.append(controller); controller.appeared()
    }
    func remove(_ controller: ViewController) {
        viewControllers.removeAll { $0 === controller }; controller.navigationController = nil; viewControllers.last?.appeared()
    }
    func replace(_ old: ViewController, with controller: ViewController) {
        viewControllers.removeAll { $0 === old }; old.navigationController = nil; pushViewController(controller)
    }
}
final class PeerSelectionController: ViewController {
    let params: PeerSelectionControllerParams
    var peerSelected: ((EnginePeer, Int64?) -> Void)?
    init(_ params: PeerSelectionControllerParams) { self.params = params }
}
final class ChannelMembersSearchController: ViewController {
    let params: ChannelMembersSearchControllerParams
    init(_ params: ChannelMembersSearchControllerParams) { self.params = params }
}
typealias ItemListSectionId = Int32
enum ItemListStyle { case blocks }
enum ItemListSystemStyle { case glass }
struct PresentationDateTimeFormat { }
struct ItemListPresentationData { let nameDisplayOrder: String; init(_ data: TestPresentationData) { nameDisplayOrder = data.nameDisplayOrder } }
struct ItemListBackButton { let title: String }
enum ItemListControllerTitle: Equatable { case text(String), textWithSubtitle(String, String) }
struct ItemListControllerState {
    let presentationData: ItemListPresentationData; let title: ItemListControllerTitle
    let leftNavigationButton: Int?; let rightNavigationButton: Int?; let backNavigationButton: ItemListBackButton?
}
protocol ItemListNodeEntry: Equatable, Comparable {
    associatedtype StableId: Hashable
    var stableId: StableId { get }; var section: ItemListSectionId { get }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem
}
class ListViewItem { }
struct ItemListNodeState {
    let makeItems: (ItemListPresentationData, Any) -> [ListViewItem]
    init<E: ItemListNodeEntry>(presentationData: ItemListPresentationData, entries: [E], style: ItemListStyle, emptyStateItem: Int?, animateChanges: Bool) {
        makeItems = { data, arguments in entries.map { $0.item(presentationData: data, arguments: arguments) } }
    }
}
final class ItemListController: ViewController {
    var title: ItemListControllerTitle?
    var backTitle: String?
    var items: [ListViewItem] = []
    var didAppear: ((Bool) -> Void)?
    private var appearedOnce = false
    private var disposable: Disposable?
    init(context: AccountContext, state: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError>) {
        super.init()
        disposable = state.start(next: { [weak self] state, body in
            self?.title = state.title; self?.backTitle = state.backNavigationButton?.title
            self?.items = body.0.makeItems(state.presentationData, body.1)
        })
    }
    override func appeared() { let first = !appearedOnce; appearedOnce = true; didAppear?(first) }
    deinit { disposable?.dispose() }
}
enum ItemListText { case plain(String) }
final class ItemListTextItem: ListViewItem {
    let text: ItemListText
    init(presentationData: ItemListPresentationData, text: ItemListText, sectionId: ItemListSectionId) { self.text = text }
}
enum ItemListActionKind { case generic }
enum ItemListActionAlignment { case natural }
final class ItemListActionItem: ListViewItem {
    let title: String; let action: () -> Void
    init(presentationData: ItemListPresentationData, systemStyle: ItemListSystemStyle = .glass, title: String, kind: ItemListActionKind, alignment: ItemListActionAlignment, sectionId: ItemListSectionId, style: ItemListStyle, action: @escaping () -> Void) { self.title = title; self.action = action }
}
enum ItemListPeerItemText {
    enum Color { case secondary }
    case none, text(String, Color)
    var string: String { if case let .text(value, _) = self { return value }; return "" }
}
enum ItemListPeerItemLabel { case none }
struct ItemListPeerItemEditing { let editable: Bool; let editing: Bool; let revealed: Bool }
final class ItemListPeerItem: ListViewItem {
    let peer: EnginePeer; let text: ItemListPeerItemText; let action: () -> Void
    let removePeer: (EnginePeer.Id) -> Void
    let editing: ItemListPeerItemEditing
    init(presentationData: ItemListPresentationData, systemStyle: ItemListSystemStyle, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: String, context: AccountContext, peer: EnginePeer, presence: Int?, text: ItemListPeerItemText, label: ItemListPeerItemLabel, editing: ItemListPeerItemEditing, enabled: Bool, selectable: Bool, sectionId: ItemListSectionId, action: @escaping () -> Void, setPeerIdWithRevealedOptions: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void, removePeer: @escaping (EnginePeer.Id) -> Void) {
        self.peer = peer; self.text = text; self.action = action; self.removePeer = removePeer; self.editing = editing
    }
}
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    static let contentFiltersDidChangeNotification = Notification.Name("test.group-member-filters")
    var groupHiddenSenders = RGGroupMemberSelection()
    var groupNotificationSenders = RGGroupMemberSelection()
    var blockedPeerIds: Set<Int64> = []
    func changed() { NotificationCenter.default.post(name: Self.contentFiltersDidChangeNotification, object: nil) }
    func setGroupMemberHidden(accountId: Int64, groupId: Int64, senderId: Int64, hidden: Bool) {
        groupHiddenSenders.set(accountId: accountId, groupId: groupId, senderId: senderId, selected: hidden); changed()
    }
    func setGroupMemberReminder(accountId: Int64, groupId: Int64, senderId: Int64, enabled: Bool) {
        groupNotificationSenders.set(accountId: accountId, groupId: groupId, senderId: senderId, selected: enabled); changed()
    }
}
func rgContentFiltersDidChange() -> Signal<Void, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: nil) { _ in subscriber.putNext(()) }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}
extension String {
    func i18n(_ lang: String) -> String {
        if self.hasSuffix(".Count") { return "%d members" }
        return self
    }
}

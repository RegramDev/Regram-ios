import Foundation
import AccountContext
import Display
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

public enum RGGroupMemberSettingsMode: Equatable {
    case hidden, reminders

    fileprivate var prefix: String { self == .hidden ? "GroupMembers.Hidden" : "GroupMembers.Reminders" }
    fileprivate var selection: RGGroupMemberSelection {
        self == .hidden ? RGSimpleSettings.shared.groupHiddenSenders : RGSimpleSettings.shared.groupNotificationSenders
    }
    fileprivate func set(accountId: Int64, groupId: Int64, senderId: Int64, selected: Bool) {
        switch self {
        case .hidden: RGSimpleSettings.shared.setGroupMemberHidden(accountId: accountId, groupId: groupId, senderId: senderId, hidden: selected)
        case .reminders: RGSimpleSettings.shared.setGroupMemberReminder(accountId: accountId, groupId: groupId, senderId: senderId, enabled: selected)
        }
    }
}

private final class RGGroupMemberSettingsArguments {
    let context: AccountContext
    let add: () -> Void
    let open: (EnginePeer) -> Void
    let remove: (EnginePeer.Id) -> Void
    let reveal: (EnginePeer.Id?, EnginePeer.Id?) -> Void
    init(context: AccountContext, add: @escaping () -> Void, open: @escaping (EnginePeer) -> Void, remove: @escaping (EnginePeer.Id) -> Void, reveal: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void) {
        self.context = context; self.add = add; self.open = open; self.remove = remove; self.reveal = reveal
    }
}

private enum RGGroupMemberSettingsEntryId: Hashable { case notice, add, peer(EnginePeer.Id) }
private enum RGGroupMemberSettingsEntry: ItemListNodeEntry {
    case notice(String)
    case add(String)
    case peer(Int, EnginePeer, Bool)

    var section: ItemListSectionId { if case .notice = self { return 0 }; return 1 }
    var stableId: RGGroupMemberSettingsEntryId {
        switch self {
        case .notice: return .notice
        case .add: return .add
        case let .peer(_, peer, _): return .peer(peer.id)
        }
    }
    private var index: Int {
        switch self { case .notice: return 0; case .add: return 1; case let .peer(index, _, _): return index + 2 }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.index < rhs.index }
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.notice(lhs), .notice(rhs)), let (.add(lhs), .add(rhs)): return lhs == rhs
        case let (.peer(li, lp, lr), .peer(ri, rp, rr)): return li == ri && lp == rp && lr == rr
        default: return false
        }
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGGroupMemberSettingsArguments
        switch self {
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .add(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.add)
        case let .peer(_, peer, revealed):
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: PresentationDateTimeFormat(), nameDisplayOrder: presentationData.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: revealed), enabled: true, selectable: true, sectionId: self.section, action: { arguments.open(peer) }, setPeerIdWithRevealedOptions: arguments.reveal, removePeer: arguments.remove)
        }
    }
}

/// With no group selected, lists this account's configured groups. Each group owns a member list.
public func rgGroupMemberSettingsController(context: AccountContext, groupId: EnginePeer.Id? = nil, mode: RGGroupMemberSettingsMode) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let revealed = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)
    var push: ((ViewController) -> Void)?
    var present: ((ViewController) -> Void)?

    func selectedIds() -> Set<Int64> {
        if let groupId { return mode.selection.senderIds(accountId: accountId, groupId: groupId.toInt64()) }
        return mode.selection.groupIds(accountId: accountId)
    }

    let arguments = RGGroupMemberSettingsArguments(context: context, add: {
        if let groupId {
            var dismissPicker: (() -> Void)?
            // Reuse Telegram's member picker with non-members excluded; selecting only updates local preferences.
            let picker = context.sharedContext.makeChannelMembersSearchController(params: ChannelMembersSearchControllerParams(context: context, peerId: groupId, mode: .select, filters: [.excludeNonMembers, .exclude(selectedIds().map(EnginePeer.Id.init) + [context.account.peerId])], openPeer: { peer, _ in
                guard peer.id != context.account.peerId else { return }
                mode.set(accountId: accountId, groupId: groupId.toInt64(), senderId: peer.id.toInt64(), selected: true)
                dismissPicker?()
            }))
            dismissPicker = { [weak picker] in picker?.dismiss() }
            present?(picker)
        } else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyGroups, .excludeRecent, .doNotSearchMessages, .removeSearchHeader], title: "GroupMembers.SelectGroup".i18n(presentationData.strings.rgLanguageCode)))
            picker.peerSelected = { [weak picker] peer, _ in
                picker?.dismiss()
                push?(rgGroupMemberSettingsController(context: context, groupId: peer.id, mode: mode))
            }
            present?(picker)
        }
    }, open: { peer in
        if groupId == nil {
            push?(rgGroupMemberSettingsController(context: context, groupId: peer.id, mode: mode))
        } else if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            push?(controller)
        }
    }, remove: { peerId in
        if let groupId {
            mode.set(accountId: accountId, groupId: groupId.toInt64(), senderId: peerId.toInt64(), selected: false)
        } else {
            for senderId in mode.selection.senderIds(accountId: accountId, groupId: peerId.toInt64()) {
                mode.set(accountId: accountId, groupId: peerId.toInt64(), senderId: senderId, selected: false)
            }
        }
    }, reveal: { peerId, fromPeerId in
        let _ = (revealed.get() |> take(1)).start(next: { current in
            if (peerId == nil && fromPeerId == current) || (peerId != nil && fromPeerId == nil) { revealed.set(peerId) }
        })
    })

    let changes: Signal<Void, NoError> = .single(()) |> then(rgContentFiltersDidChange())
    let peers: Signal<[EnginePeer], NoError> = changes |> mapToSignal { _ in
        let ids = selectedIds().sorted().map(EnginePeer.Id.init)
        if ids.isEmpty { return .single([]) }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:)))) |> map { peerMap in
            ids.map { id in
                if let value = peerMap[id], let peer = value { return peer }
                return EnginePeer.user(TelegramUser(id: id, accessHash: nil, firstName: "ID \(id.id._internalGetInt64Value())", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
            }.sorted { $0.compactDisplayTitle.localizedCaseInsensitiveCompare($1.compactDisplayTitle) == .orderedAscending }
        }
    }
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, peers, revealed.get()) |> map { presentationData, peers, revealed -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.rgLanguageCode
        var entries: [RGGroupMemberSettingsEntry] = [.notice("\(mode.prefix).Notice".i18n(lang)), .add((groupId == nil ? "GroupMembers.AddGroup" : "GroupMembers.AddMember").i18n(lang))]
        entries.append(contentsOf: peers.enumerated().map { .peer($0.offset, $0.element, $0.element.id == revealed) })
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("\(mode.prefix).Title".i18n(lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: nil, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    push = { [weak controller] in (controller?.navigationController as? NavigationController)?.pushViewController($0) }
    present = { [weak controller] in controller?.present($0, in: .window(.root)) }
    return controller
}

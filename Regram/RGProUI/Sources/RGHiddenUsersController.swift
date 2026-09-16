import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import PresentationDataUtils
import AccountContext
import LocalizedPeerData
import RGSimpleSettings
import RGStrings

// MARK: Regram
// The list of senders whose messages are hidden (toggled from their profile). Reached from the
// Regram Pro screen. Peers are resolved through the engine so the rows show real names and avatars;
// a peer that cannot be resolved (never loaded on this device) is still listed by id so it can be
// removed. Rows can be swiped to unhide, tapped to open the profile, and reordering is not offered
// because order carries no meaning here.

private final class RGHiddenUsersArguments {
    let context: AccountContext
    let openPeer: (EnginePeer) -> Void
    let removePeer: (EnginePeer.Id) -> Void
    let setPeerIdWithRevealedOptions: (EnginePeer.Id?, EnginePeer.Id?) -> Void

    init(context: AccountContext, openPeer: @escaping (EnginePeer) -> Void, removePeer: @escaping (EnginePeer.Id) -> Void, setPeerIdWithRevealedOptions: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void) {
        self.context = context
        self.openPeer = openPeer
        self.removePeer = removePeer
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
    }
}

private enum RGHiddenUsersSection: Int32 {
    case peers
}

private enum RGHiddenUsersEntryId: Hashable {
    case notice
    case peer(EnginePeer.Id)
}

private enum RGHiddenUsersEntry: ItemListNodeEntry {
    case notice(String)
    case peer(index: Int, peer: EnginePeer, revealed: Bool)

    var section: ItemListSectionId {
        return RGHiddenUsersSection.peers.rawValue
    }

    var stableId: RGHiddenUsersEntryId {
        switch self {
        case .notice:
            return .notice
        case let .peer(_, peer, _):
            return .peer(peer.id)
        }
    }

    static func ==(lhs: RGHiddenUsersEntry, rhs: RGHiddenUsersEntry) -> Bool {
        switch lhs {
        case let .notice(text):
            if case .notice(text) = rhs {
                return true
            }
            return false
        case let .peer(lhsIndex, lhsPeer, lhsRevealed):
            if case let .peer(rhsIndex, rhsPeer, rhsRevealed) = rhs, lhsIndex == rhsIndex, lhsPeer == rhsPeer, lhsRevealed == rhsRevealed {
                return true
            }
            return false
        }
    }

    static func <(lhs: RGHiddenUsersEntry, rhs: RGHiddenUsersEntry) -> Bool {
        switch lhs {
        case .notice:
            return true
        case let .peer(lhsIndex, _, _):
            switch rhs {
            case .notice:
                return false
            case let .peer(rhsIndex, _, _):
                return lhsIndex < rhsIndex
            }
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGHiddenUsersArguments
        switch self {
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .peer(_, peer, revealed):
            return ItemListPeerItem(
                presentationData: presentationData,
                dateTimeFormat: PresentationDateTimeFormat(),
                nameDisplayOrder: presentationData.nameDisplayOrder,
                context: arguments.context,
                peer: peer,
                presence: nil,
                text: .none,
                label: .none,
                editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: revealed),
                enabled: true,
                selectable: true,
                sectionId: self.section,
                action: {
                    arguments.openPeer(peer)
                },
                setPeerIdWithRevealedOptions: { previousId, id in
                    arguments.setPeerIdWithRevealedOptions(previousId, id)
                },
                removePeer: { peerId in
                    arguments.removePeer(peerId)
                }
            )
        }
    }
}

/// A placeholder for an id whose peer is not in the local database, so the row can still be shown
/// and removed instead of silently vanishing from the list.
private func rgPlaceholderPeer(id: EnginePeer.Id, title: String) -> EnginePeer {
    return .user(TelegramUser(id: id, accessHash: nil, firstName: title, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
}

public func rgHiddenUsersController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise<Set<Int64>>(RGSimpleSettings.shared.blockedPeerIds, ignoreRepeated: true)
    let revealedPeerId = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = RGHiddenUsersArguments(context: context, openPeer: { peer in
        if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            pushControllerImpl?(controller)
        }
    }, removePeer: { peerId in
        RGSimpleSettings.shared.setPeerBlocked(peerId.toInt64(), blocked: false)
        statePromise.set(RGSimpleSettings.shared.blockedPeerIds)
    }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        // Standard reveal bookkeeping: only accept the change if it is about the currently
        // revealed row (or none is revealed), so two rows never show options at once.
        let _ = (revealedPeerId.get() |> take(1)).start(next: { current in
            if (peerId == nil && fromPeerId == current) || (peerId != nil && fromPeerId == nil) {
                revealedPeerId.set(peerId)
            }
        })
    })

    let peers: Signal<[EnginePeer], NoError> = statePromise.get()
    |> mapToSignal { ids -> Signal<[EnginePeer], NoError> in
        let peerIds = ids.map { EnginePeer.Id($0) }
        if peerIds.isEmpty {
            return .single([])
        }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peerMap -> [EnginePeer] in
            var result: [EnginePeer] = []
            for id in peerIds {
                if let maybePeer = peerMap[id], let peer = maybePeer {
                    result.append(peer)
                } else {
                    result.append(rgPlaceholderPeer(id: id, title: "ID \(id.id._internalGetInt64Value())"))
                }
            }
            // Stable, readable order: by display name.
            return result.sorted { $0.compactDisplayTitle.localizedCaseInsensitiveCompare($1.compactDisplayTitle) == .orderedAscending }
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, peers, revealedPeerId.get())
    |> map { presentationData, peers, revealedPeerId -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [RGHiddenUsersEntry] = []
        if peers.isEmpty {
            entries.append(.notice("HiddenUsers.Empty".i18n(lang)))
        } else {
            entries.append(.notice("HiddenUsers.Notice".i18n(lang)))
            for (index, peer) in peers.enumerated() {
                entries.append(.peer(index: index, peer: peer, revealed: revealedPeerId == peer.id))
            }
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("HiddenUsers.Title".i18n(lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    // Reflect toggles made from profile screens while this list is open.
    controller.didAppear = { _ in
        statePromise.set(RGSimpleSettings.shared.blockedPeerIds)
    }
    return controller
}

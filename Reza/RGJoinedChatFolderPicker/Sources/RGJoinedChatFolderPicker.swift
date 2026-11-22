import Foundation
import AccountContext
import Display
import LocalizedPeerData
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UndoUI

// MARK: Regram — "Choose Folder After Joining" (RGSimpleSettings.chooseFolderAfterJoining).
//
// Called once a join of a group or channel has succeeded. Offers the account's chat folders that can
// still take the chat and adds it to the chosen folder's include list, with the same limits as the
// chat list's "Add to Folder" context action (ChatListUI/ChatContextMenus.swift). Presents nothing
// when the setting is off, the account has no folders, or no folder can take the chat.
public func rgPresentFolderPickerAfterJoining(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void) {
    guard RGSimpleSettings.shared.chooseFolderAfterJoining else {
        return
    }
    rgPresentChatFolderPicker(context: context, peerId: peerId, hideWhenEmpty: true, present: present)
}

public func rgPresentChatFolderPicker(context: AccountContext, peerId: EnginePeer.Id, hideWhenEmpty: Bool = false, present: @escaping (ViewController) -> Void) {
    // A folder matches a secret chat by its associated user, never by its own id.
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return
    }
    let _ = (combineLatest(
        context.engine.peers.updatedChatListFilters()
        |> take(1),
        context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId),
            TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: false),
            TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: true),
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.NotificationSettings(id: peerId),
            TelegramEngine.EngineData.Item.NotificationSettings.Global()
        )
    )
    |> deliverOnMainQueue).startStandalone(next: { filters, values in
        let (accountPeer, limits, premiumLimits, peer, notificationSettings, globalNotificationSettings) = values
        guard let peer else {
            return
        }
        // Local Premium changes presentation only; folder limits use the real account flag.
        let isPremium: Bool
        if case let .user(user)? = accountPeer { isPremium = user.flags.contains(.isPremium) } else { isPremium = false }
        let limit = Int(isPremium ? premiumLimits.maxFolderChatsCount : limits.maxFolderChatsCount)
        let isMuted = rgJoinedPeerIsMuted(peer: peer, notificationSettings: notificationSettings, globalNotificationSettings: globalNotificationSettings)

        var candidates: [(id: Int32, title: ChatFolderTitle)] = []
        for case let .filter(id, title, _, data) in filters {
            if rgFolderAlreadyShows(data: data, peer: peer, isMuted: isMuted) {
                continue
            }
            if data.includePeers.peers.count >= limit {
                continue
            }
            var updatedData = data
            if !updatedData.addIncludePeer(peerId: peer.id) {
                continue
            }
            candidates.append((id, title))
        }
        if candidates.isEmpty {
            if !hideWhenEmpty {
                rgPresentEmptyFolderPicker(presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: present)
            }
            return
        }

        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let chatTitle = peer.compactDisplayTitle

        let controller = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [
            ActionSheetTextItem(title: i18n("JoinFolder.Picker.Title", lang, chatTitle), parseMarkdown: false)
        ]
        for candidate in candidates {
            items.append(ActionSheetButtonItem(title: candidate.title.text, color: .accent, action: { [weak controller] in
                controller?.dismissAnimated()
                rgAddJoinedPeer(context: context, peerId: peer.id, chatTitle: chatTitle, folderId: candidate.id, folderTitle: candidate.title, limit: limit, presentationData: presentationData, present: present)
            }))
        }
        controller.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak controller] in
                    controller?.dismissAnimated()
                })
            ])
        ])
        present(controller)
    })
}

private func rgAddJoinedPeer(context: AccountContext, peerId: EnginePeer.Id, chatTitle: String, folderId: Int32, folderTitle: ChatFolderTitle, limit: Int, presentationData: PresentationData, present: @escaping (ViewController) -> Void) {
    // The folders may have changed while the sheet was open, so the limit is checked again here.
    let _ = (context.engine.peers.updateChatListFiltersInteractively { filters in
        return filters.map { filter -> ChatListFilter in
            guard case let .filter(id, title, emoticon, data) = filter, id == folderId else {
                return filter
            }
            if data.includePeers.peers.count >= limit {
                return filter
            }
            var updatedData = data
            if !updatedData.addIncludePeer(peerId: peerId) {
                return filter
            }
            return .filter(id: id, title: title, emoticon: emoticon, data: updatedData)
        }
    }
    |> deliverOnMainQueue).startStandalone(next: { filters in
        let added = filters.contains(where: { filter in
            if case let .filter(id, _, _, data) = filter, id == folderId {
                return data.includePeers.peers.contains(peerId) || data.includePeers.pinnedPeers.contains(peerId)
            }
            return false
        })
        if added {
            present(UndoOverlayController(presentationData: presentationData, content: .chatAddedToFolder(context: context, chatTitle: chatTitle, folderTitle: folderTitle.rawAttributedString), elevatedLayout: false, animateInAsReplacement: false, action: { _ in
                return false
            }))
        } else {
            let alert = ActionSheetController(presentationData: presentationData)
            alert.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: i18n("JoinFolder.Unavailable", presentationData.strings.baseLanguageCode), parseMarkdown: false),
                    ActionSheetButtonItem(title: presentationData.strings.Common_OK, color: .accent, font: .bold, action: { [weak alert] in
                        alert?.dismissAnimated()
                    })
                ])
            ])
            present(alert)
        }
    })
}

// Mirrors chatContextMenuPeerIsMuted (ChatListUI) for the chat kinds that can be joined.
private func rgJoinedPeerIsMuted(peer: EnginePeer, notificationSettings: EnginePeer.NotificationSettings, globalNotificationSettings: EngineGlobalNotificationSettings) -> Bool {
    switch notificationSettings.muteState {
    case let .muted(until):
        return until >= Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    case .unmuted:
        return false
    case .default:
        switch peer {
        case .user:
            return !globalNotificationSettings.privateChats.enabled
        case .legacyGroup:
            return !globalNotificationSettings.groupChats.enabled
        case let .channel(channel):
            switch channel.info {
            case .group:
                return !globalNotificationSettings.groupChats.enabled
            case .broadcast:
                return !globalNotificationSettings.channels.enabled
            }
        case .community:
            return true
        case .secretChat:
            return false
        }
    }
}

// Whether the folder already lists the chat, explicitly or through its chat-type categories.
// The category half is the part of chatListFilterPredicate (ChatListUI) that applies to a group or
// channel that was just joined (in the main list, not archived); a folder that hides read chats is
// treated as not showing it, since a joined chat with nothing unread drops out of it.
private func rgFolderAlreadyShows(data: ChatListFilterData, peer: EnginePeer, isMuted: Bool) -> Bool {
    if data.includePeers.peers.contains(peer.id) || data.includePeers.pinnedPeers.contains(peer.id) {
        return true
    }
    if data.excludePeers.contains(peer.id) {
        return false
    }
    if data.excludeRead {
        return false
    }
    if data.excludeMuted && isMuted {
        return false
    }
    switch peer {
    case .legacyGroup, .community:
        return data.categories.contains(.groups)
    case let .channel(channel):
        switch channel.info {
        case .group:
            return data.categories.contains(.groups)
        case .broadcast:
            return data.categories.contains(.channels)
        }
    case .user, .secretChat:
        return false
    }
}

// MARK: Regram — keep the manual empty state outside the typed engine-data closure.
private func rgPresentEmptyFolderPicker(presentationData: PresentationData, present: @escaping (ViewController) -> Void) {
    let controller = ActionSheetController(presentationData: presentationData)
    let title = "features.ChatFolderNoneAvailable".i18n(presentationData.strings.baseLanguageCode)
    let items: [ActionSheetItem] = [
        ActionSheetTextItem(title: title),
        ActionSheetButtonItem(title: presentationData.strings.Common_OK, color: .accent, action: { [weak controller] in controller?.dismissAnimated() })
    ]
    controller.setItemGroups([ActionSheetItemGroup(items: items)])
    present(controller)
}

// MARK: Regram — choose the startup destination directly from the folders settings row.
import Display
import RGSimpleSettings
import RGStrings
import TelegramCore
import TelegramPresentationData

func rgStartupFolderTitle(filters: [ChatListFilter], accountId: Int64, presentationData: PresentationData) -> String {
    let settings = RGSimpleSettings.shared
    let lang = presentationData.strings.rgLanguageCode
    switch settings.chatListStartupFolderModeValue {
    case .telegramDefault, .last:
        return ("features.ChatListStartupFolder." + settings.chatListStartupFolderModeValue.rawValue).i18n(lang)
    case .specific:
        guard let folderId = settings.chatListStartupSpecificFolderId(accountPeerId: accountId) else {
            return "features.ChatListStartupFolder.notSet".i18n(lang)
        }
        if folderId == RGSimpleSettings.chatListAllChatsFolderId { return presentationData.strings.ChatList_Tabs_AllChats }
        for case let .filter(id, title, _, _) in filters where id == folderId { return title.text }
        return "features.ChatListStartupFolder.Unavailable".i18n(lang)
    }
}

func rgStartupFolderActionItems(filters: [ChatListFilter], accountId: Int64, presentationData: PresentationData, dismiss: @escaping () -> Void, updated: @escaping () -> Void) -> [ActionSheetItem] {
    let lang = presentationData.strings.rgLanguageCode
    var items: [ActionSheetItem] = []
    for mode in [RGFeatureChatListStartupFolderMode.telegramDefault, .last] {
        items.append(ActionSheetButtonItem(title: ("features.ChatListStartupFolder." + mode.rawValue).i18n(lang), color: .accent, action: {
            dismiss()
            RGSimpleSettings.shared.chatListStartupFolderMode = mode.rawValue
            updated()
        }))
    }
    var folders: [(Int32, String)] = [(RGSimpleSettings.chatListAllChatsFolderId, presentationData.strings.ChatList_Tabs_AllChats)]
    for case let .filter(id, title, _, _) in filters { folders.append((id, title.text)) }
    for (id, title) in folders {
        items.append(ActionSheetButtonItem(title: title, color: .accent, action: {
            dismiss()
            RGSimpleSettings.shared.setChatListStartupSpecificFolderId(id, accountPeerId: accountId)
            RGSimpleSettings.shared.chatListStartupFolderMode = RGFeatureChatListStartupFolderMode.specific.rawValue
            updated()
        }))
    }
    return items
}

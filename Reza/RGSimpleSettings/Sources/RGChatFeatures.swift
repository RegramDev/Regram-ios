// MARK: Regram — local chat/interface features; settings remain in the existing backup flow.
import Foundation

public final class RGFeaturePreferences {
    public static let shared = RGFeaturePreferences()
    public static func key(_ value: String) -> String {
        let suffix = value.hasPrefix("features.") ? String(value.dropFirst(9)) : value
        if RGSimpleSettings.Keys.allCases.contains(where: { $0.rawValue == suffix }) { return suffix }
        return value.hasPrefix("features.") ? value : "features." + value
    }
    public func set(_ value: Any, forKey key: String) {
        let resolvedKey = Self.key(key)
        let storage = UserDefaults.standard
        let oldValue = storage.object(forKey: resolvedKey) as? Bool
        storage.set(value, forKey: resolvedKey)
        if resolvedKey == "features.showFoldersInShareSheet" {
            NotificationCenter.default.post(name: RGSimpleSettings.shareSettingsDidChange, object: nil)
        }
        if resolvedKey == "features.enablePanguOnReceiving", oldValue != value as? Bool {
            NotificationCenter.default.post(name: RGSimpleSettings.featureMessagePresentationDidChange, object: nil)
        }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
    }
    public func removeObject(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: Self.key(key))
        if Self.key(key) == "features.showFoldersInShareSheet" {
            NotificationCenter.default.post(name: RGSimpleSettings.shareSettingsDidChange, object: nil)
        }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
    }
    public static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        return UserDefaults.standard.object(forKey: Self.key(key)) as? Bool ?? defaultValue
    }
    public static func string(_ key: String, default defaultValue: String) -> String {
        return UserDefaults.standard.string(forKey: Self.key(key)) ?? defaultValue
    }
}

public enum RGFeatureChatListSwipeAction: String, CaseIterable {
    case both, folderSwitch = "switch", quickActions = "quick", none
    public var allowsFolderSwitch: Bool { self == .both || self == .folderSwitch }
    public var allowsQuickActions: Bool { self == .both || self == .quickActions }
}
public enum RGFeatureCommunityAvatarTapAction: String, CaseIterable { case chat, community, arrow }
public enum RGFeatureChatListStartupFolderMode: String, CaseIterable { case telegramDefault = "telegram", last, specific }
public enum RGFeatureChatListFolderTabDisplayMode: String, CaseIterable { case text, icon, iconAndText = "both" }
public enum RGFeatureGroupProfileSettingItem: String, CaseIterable, Hashable {
    case groupType, inviteLinks, linkedChannel, reactions, appearance, history, topics, location
    case members, permissions, admins, memberRequests, removedUsers, recentActions, community, deleteGroup, other
}

public extension RGSimpleSettings {
    static var featureMessagePresentationDidChange: Notification.Name { Notification.Name("RGFeatureMessagePresentationDidChange") }

    var showFoldersInShareSheet: Bool {
        get { RGFeaturePreferences.bool("features.showFoldersInShareSheet") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.showFoldersInShareSheet") }
    }
    var autoInlineBotEnabled: Bool {
        get { RGFeaturePreferences.bool("features.autoInlineBotEnabled") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.autoInlineBotEnabled") }
    }
    var hideSavedAndArchivedMessagesInList: Bool {
        get { RGFeaturePreferences.bool("features.hideSavedAndArchivedMessagesInList") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.hideSavedAndArchivedMessagesInList") }
    }
    var hidePrivateChatActivities: Bool {
        get { RGFeaturePreferences.bool("features.hidePrivateChatActivities") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.hidePrivateChatActivities") }
    }
    var tapMessageRowToOpenContextMenu: Bool {
        get { RGFeaturePreferences.bool("features.tapMessageRowToOpenContextMenu") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.tapMessageRowToOpenContextMenu") }
    }
    var confirmUnpin: Bool {
        get { RGFeaturePreferences.bool("features.confirmUnpin") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.confirmUnpin") }
    }
    var hideFolderUnreadCount: Bool {
        get { RGFeaturePreferences.bool("features.hideFolderUnreadCount") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.hideFolderUnreadCount") }
    }
    var showArchiveInFolders: Bool {
        get { RGFeaturePreferences.bool("features.showArchiveInFolders") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.showArchiveInFolders") }
    }
    var stayAtLatestMessageAfterRefresh: Bool {
        get { RGFeaturePreferences.bool("features.stayAtLatestMessageAfterRefresh") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.stayAtLatestMessageAfterRefresh") }
    }
    var enablePanguOnEditing: Bool {
        get { RGFeaturePreferences.bool("features.enablePanguOnEditing") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.enablePanguOnEditing") }
    }
    var enablePanguOnReceiving: Bool {
        get { RGFeaturePreferences.bool("features.enablePanguOnReceiving") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.enablePanguOnReceiving") }
    }
    var hideTopStories: Bool {
        get { RGFeaturePreferences.bool("features.hideTopStories") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.hideTopStories") }
    }
    var disableChatAvatarStories: Bool {
        get { RGFeaturePreferences.bool("features.disableChatAvatarStories") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.disableChatAvatarStories") }
    }
    var hideTabBarPermissionWarnings: Bool {
        get { RGFeaturePreferences.bool("features.hideTabBarPermissionWarnings") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.hideTabBarPermissionWarnings") }
    }
    var keepNewChatsVisibleAtTop: Bool {
        get { RGFeaturePreferences.bool("features.keepNewChatsVisibleAtTop") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.keepNewChatsVisibleAtTop") }
    }
    var chatListStartupFolderMode: String {
        get { RGFeaturePreferences.string("features.chatListStartupFolderMode", default: "telegram") }
        set {
            guard let mode = RGFeatureChatListStartupFolderMode(rawValue: newValue) else { return }
            rememberLastFolder = mode == .last
            RGFeaturePreferences.shared.set(mode.rawValue, forKey: "features.chatListStartupFolderMode")
        }
    }
    var chatListFolderTabDisplayMode: String {
        get { RGFeaturePreferences.string("features.chatListFolderTabDisplayMode", default: "text") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.chatListFolderTabDisplayMode") }
    }
    var communityAvatarTapAction: String {
        get { RGFeaturePreferences.string("features.communityAvatarTapAction", default: "community") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.communityAvatarTapAction") }
    }
    var videoPIPSwipeDirection: String {
        get { RGFeaturePreferences.string("features.videoPIPSwipeDirection", default: "up") }
        set { RGFeaturePreferences.shared.set(newValue, forKey: "features.videoPIPSwipeDirection") }
    }
    static var chatListAllChatsFolderId: Int32 { -1 }
    var chatListFolderTabsCompact: Bool { get { compactFolderNames } set { compactFolderNames = newValue } }
    var enablePanguOnSending: Bool { get { panguSpacing } set { panguSpacing = newValue } }
    var hideTabBarContacts: Bool { !bottomBarSettings.isVisible(.contacts) }
    var showTabBarSearch: Bool { bottomBarSettings.searchMode != .hidden }
    var chatListSwipeAction: String {
        get { RGFeaturePreferences.string("features.chatListSwipeAction", default: disableChatSwipeOptions ? "none" : "both") }
        set {
            disableChatSwipeOptions = newValue == "none"
            RGFeaturePreferences.shared.set(newValue, forKey: "features.chatListSwipeAction")
        }
    }
    var chatListSwipeActionMode: RGFeatureChatListSwipeAction { RGFeatureChatListSwipeAction(rawValue: chatListSwipeAction) ?? .both }
    var chatListStartupFolderModeValue: RGFeatureChatListStartupFolderMode {
        RGFeatureChatListStartupFolderMode(rawValue: RGFeaturePreferences.string("features.chatListStartupFolderMode", default: rememberLastFolder ? "last" : "telegram")) ?? .telegramDefault
    }
    var chatListFolderTabDisplayModeValue: RGFeatureChatListFolderTabDisplayMode { RGFeatureChatListFolderTabDisplayMode(rawValue: chatListFolderTabDisplayMode) ?? .text }
    var communityAvatarTapActionValue: RGFeatureCommunityAvatarTapAction { RGFeatureCommunityAvatarTapAction(rawValue: communityAvatarTapAction) ?? .community }
    var disableStoryCameraSwipeEffective: Bool { hideStories || disableSwipeToRecordStory }
    var disableChatAvatarStoriesEffective: Bool { hideStories || disableChatAvatarStories }
    func chatListStartupSpecificFolderId(accountPeerId: Int64) -> Int32? {
        let values = UserDefaults.standard.dictionary(forKey: "features.startupFolders") as? [String: String] ?? [:]
        return values[String(accountPeerId)].flatMap(Int32.init)
    }
    func setChatListStartupSpecificFolderId(_ value: Int32?, accountPeerId: Int64) {
        var values = UserDefaults.standard.dictionary(forKey: "features.startupFolders") as? [String: String] ?? [:]
        values[String(accountPeerId)] = value.map(String.init)
        RGFeaturePreferences.shared.set(values, forKey: "features.startupFolders")
    }
    func chatListStartupLastFolderId(accountPeerId: Int64) -> Int32? {
        lastAccountFolders[String(PeerIdCompat(accountPeerId))]
    }
    func setChatListStartupLastFolderId(_ value: Int32?, accountPeerId: Int64) {
        if let value { lastAccountFolders[String(PeerIdCompat(accountPeerId))] = value }
    }
    func isGroupProfileSettingItemVisible(_ item: RGFeatureGroupProfileSettingItem) -> Bool {
        let value = RGFeaturePreferences.string("features.groupProfileSettingItems", default: "")
        return value.split(separator: ",").contains { $0 == item.rawValue }
    }
    func setGroupProfileSettingItemVisible(_ item: RGFeatureGroupProfileSettingItem, visible: Bool) {
        var items = Set(RGFeaturePreferences.string("features.groupProfileSettingItems", default: "").split(separator: ",").map(String.init))
        if visible { items.insert(item.rawValue) } else { items.remove(item.rawValue) }
        RGFeaturePreferences.shared.set(items.sorted().joined(separator: ","), forKey: "features.groupProfileSettingItems")
    }
}
// Telegram's legacy account-folder map used the unnamespaced account id.
private func PeerIdCompat(_ value: Int64) -> Int64 { value & 0x00ffffffffffffff }

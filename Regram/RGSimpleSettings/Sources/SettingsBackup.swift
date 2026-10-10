import Foundation
import CoreFoundation

public enum RGBackupValue: Codable, Equatable {
    case bool(Bool), integer(Int64), number(Double), string(String), strings([String]), dictionary([String: String])
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Int64.self) { self = .integer(v) }
        else if let v = try? value.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([String].self) { self = .strings(v) }
        else { self = .dictionary(try value.decode([String: String].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .bool(v): try value.encode(v)
        case let .integer(v): try value.encode(v)
        case let .number(v): try value.encode(v)
        case let .string(v): try value.encode(v)
        case let .strings(v): try value.encode(v)
        case let .dictionary(v): try value.encode(v)
        }
    }
    public init?(propertyList: Any) {
        if let v = propertyList as? NSNumber {
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool(v.boolValue) }
            else if String(cString: v.objCType).contains("f") || String(cString: v.objCType).contains("d") { guard v.doubleValue.isFinite else { return nil }; self = .number(v.doubleValue) }
            else { self = .integer(v.int64Value) }
        } else if let v = propertyList as? String { self = .string(v) }
        else if let v = propertyList as? [String] { self = .strings(v) }
        else if let v = propertyList as? [String: String] { self = .dictionary(v) }
        else { return nil }
    }
    public var propertyList: Any {
        switch self {
        case let .bool(v): return v
        case let .integer(v): return v
        case let .number(v): return v
        case let .string(v): return v
        case let .strings(v): return v
        case let .dictionary(v): return v
        }
    }
}

public enum RGBackupCategory: String, Codable, CaseIterable, Identifiable {
    case appearance, messages, privacy, translation, media, notifications
    public var id: String { self.rawValue }
    public var titleKey: String { "Backup.Category." + self.rawValue }
}

public struct RGSettingsBackup: Codable {
    public enum ValidationError: Error { case tooLarge, unsupportedVersion, invalidValue(String) }
    public let version: Int
    public let createdAt: Date
    public let values: [String: RGBackupValue]
    public static let filename = "regram-settings.json"
    public static let maximumBytes = 2 * 1024 * 1024

    public init(values: [String: RGBackupValue], createdAt: Date = Date()) {
        self.version = 1; self.createdAt = createdAt
        self.values = values.filter { Self.category(for: $0.key) != nil }
    }

    public static let categoryKeys: [RGBackupCategory: [String]] = [
        .appearance: ["showTabNames", "fontFamily", "fontChineseFamily", "fontImportedLatin", "fontImportedChinese", "fontApplyToMessages", "fontApplyToInterface", "accountColorsSaturation", "rememberLastFolder", "hideReactions", "disableScrollToNextChannel", "disableScrollToNextTopic", "disableChatSwipeOptions", "disableDeleteChatSwipeOption", "disableSnapDeletionEffect", "hideTabBar", "compactChatList", "chatListLines", "compactFolderNames", "allChatsTitleLengthOverride", "allChatsHidden", "wideChannelPosts", "secondsInMessages", "hideChannelBottomButton", "customAppBadge", "tabBarWidthPercent", "hideStories", "showRepostToStoryV2", "nyStyle", "stickerSize", "stickerTimestamp", "recentStickerLimit", "native.showContactsTab", "native.showCallsTab", "native.foldersAtBottom"],
        .messages: ["contextShowSelectFromUser", "contextShowSaveToCloud", "contextShowRestrict", "contextShowHideForwardName", "contextShowReport", "contextShowReply", "contextShowPin", "contextShowSaveMedia", "contextShowMessageReplies", "contextShowJson", "contextShowRepeatForward", "contextShowRepeatCopy", "contextMenuOrder", "mentionAsUserIdLink", "disableLinkPreview", "defaultEmojisFirst", "messageDoubleTapActionOutgoing", "forceEmojiTab", "inputToolbar", "panguSpacing", "defaultOutgoingFormatting", "sendWithReturnKey", "hideRecordingButton", "disableSendAsButton", "chatPreferences"],
        .privacy: ["hidePhoneInSettings", "profileDefaultTabGroupsInCommon", "showDC", "showCreationDate", "showRegDate", "showProfileId", "confirmCalls", "messageFilterRules", "blockedPeerIds", "messageFilterDisabledPeerIds", "antiRevokePeerIds", "disableAllAds", "antiRevoke", "antiAutoDelete", "antiSelfDestruct", "antiScreenshotNotification", "allowSavingProtectedContent", "allowDownloadingStories", "ghostDontReadStories", "ghostDontSendOnline", "ghostDontSendTyping", "storyStealthMode", "disableSwipeToRecordStory", "warnOnStoriesOpen"],
        .translation: ["quickTranslateButton", "translationBackend", "transcriptionBackend", "outgoingLanguageTranslation"],
        .media: ["startTelescopeWithRearCam", "forceBuiltInMic", "uploadSpeedBoost", "downloadSpeedBoost", "mediaLoadingExperiment", "defaultVideoQuality", "localDNSForProxyHost", "sendLargePhotos", "outgoingPhotoQuality", "disableGalleryCamera", "disableGalleryCameraPreview", "forceSystemSharing", "native.enableVoipTcp"],
        .notifications: ["pinnedMessageNotifications", "mentionsAndRepliesNotifications", "pinnedMessageNotificationsExceptions", "mentionsAndRepliesNotificationsExceptions", "filterNotifications"]
    ]
    public static func category(for key: String) -> RGBackupCategory? { RGBackupCategory.allCases.first { categoryKeys[$0]?.contains(key) == true } }

    public func selectedValues(categories: Set<RGBackupCategory>) -> [String: RGBackupValue] {
        self.values.filter { Self.category(for: $0.key).map(categories.contains) == true }
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ValidationError.tooLarge }
        return data
    }
    public static func decode(_ data: Data) throws -> RGSettingsBackup {
        guard data.count <= maximumBytes else { throw ValidationError.tooLarge }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Self.self, from: data)
        guard backup.version == 1 else { throw ValidationError.unsupportedVersion }
        for (key, value) in backup.values where category(for: key) != nil {
            guard isValid(value, key: key) else { throw ValidationError.invalidValue(key) }
        }
        return RGSettingsBackup(values: backup.values, createdAt: backup.createdAt)
    }
    private static func isValid(_ value: RGBackupValue, key: String) -> Bool {
        switch key {
        case "accountColorsSaturation", "outgoingPhotoQuality":
            if case let .integer(v) = value { return (0...100).contains(v) }; return false
        case "stickerSize": if case let .integer(v) = value { return (0...200).contains(v) }; return false
        case "recentStickerLimit": if case let .integer(v) = value { return (1...1000).contains(v) }; return false
        case "tabBarWidthPercent": if case let .integer(v) = value { return v == 0 || (50...100).contains(v) }; return false
        case "contextMenuOrder", "blockedPeerIds", "messageFilterDisabledPeerIds", "antiRevokePeerIds":
            if case let .strings(v) = value { return v.count <= 10000 && v.allSatisfy { $0.utf8.count <= 128 } }; return false
        case "outgoingLanguageTranslation", "pinnedMessageNotificationsExceptions", "mentionsAndRepliesNotificationsExceptions":
            if case let .dictionary(v) = value { return v.count <= 10000 && v.allSatisfy { $0.key.utf8.count <= 128 && $0.value.utf8.count <= 128 } }; return false
        case "messageFilterRules":
            if case let .string(v) = value { return (try? JSONDecoder().decode([RGMessageFilterRule].self, from: Data(v.utf8))) != nil }; return false
        case "chatPreferences":
            if case let .string(v) = value { return (try? JSONDecoder().decode([String: RGChatPreferences].self, from: Data(v.utf8))) != nil }; return false
        case "fontImportedLatin", "fontImportedChinese":
            if case let .string(v) = value { return v.isEmpty || RGFontSelection(id: v) != nil }; return false
        case "fontFamily", "fontChineseFamily", "downloadSpeedBoost", "defaultVideoQuality", "defaultOutgoingFormatting", "chatListLines", "allChatsTitleLengthOverride", "messageDoubleTapActionOutgoing", "translationBackend", "transcriptionBackend", "customAppBadge", "nyStyle", "pinnedMessageNotifications", "mentionsAndRepliesNotifications":
            if case let .string(v) = value { return v.utf8.count <= 256 }; return false
        default: if case .bool = value { return true }; return false
        }
    }
}

import Foundation

/// Search aliases include the controls inside disclosure pages, so looking for TTF or online
/// presence leads to a usable destination even when the parent row has a different title.
public enum RGProSearchIndex {
    public static let keys: [String: [String]] = [
        "messageFilter": ["MessageFilter.Title", "MessageFilter.Regex", "MessageFilter.Test.Title", "filter regex whitelist 过滤 正则 白名单"],
        "hiddenUsers": ["HiddenUsers.Title", "hidden blocked 隐藏 屏蔽用户"],
        "inputToolbar": ["InputToolbar.Title", "format toolbar 格式 工具栏"],
        "mentionAsUserIdLink": ["Mention.UserIdLink", "mention nickname 昵称 提及 艾特"],
        "localPremium": ["LocalPremium.Title", "premium"],
        "disableLinkPreview": ["LinkPreview.Disable", "link preview 链接 预览"],
        "panguSpacing": ["Pangu.Title", "spacing 盘古 空格"],
        "defaultOutgoingFormatting": ["OutgoingFormatting.Title", "format bold italic 默认 格式 加粗 斜体"],
        "antiFeatures": ["AntiFeatures.Header", "AntiFeatures.Revoke", "AntiFeatures.AutoDelete", "AntiFeatures.SelfDestruct", "AntiFeatures.Screenshot", "AntiFeatures.SaveProtected", "AntiFeatures.SaveProtectedStories", "AntiFeatures.DisableAds", "privacy ads sponsored 隐私 广告 赞助 防撤回"],
        "antiRevokeChats": ["AntiRevoke.Chats.Title", "revoked chats 防撤回 会话"],
        "ghostMode": ["Ghost.Header", "Ghost.DontReadStories", "Ghost.DontSendOnline", "Ghost.DontSendTyping", "ghost online typing 幽灵 在线 输入状态 快拍"],
        "pinnedMessageNotifications": ["Notifications.PinnedMessages.Title", "pinned notification 置顶 通知"],
        "mentionsAndRepliesNotifications": ["Notifications.MentionsAndReplies.Title", "mention reply notification 提及 回复 通知"],
        "fonts": ["Fonts.Title", "Fonts.Import", "Fonts.Storage", "font 字体 字體 字型 TTF OTF TTC JetBrains Anthropic Google 中文 英文 下载 下載 导入 匯入"],
        "appIcons": ["icon 图标 圖標"],
        "appBages": ["AppBadge.Title", "badge 标记 截图"],
        "eraseAllData": ["EraseData.Title", "erase reset 清除数据"],
        "backup": ["Backup.Title", "Backup.Import", "Backup.Export", "backup restore 备份 備份 恢复 還原 配置"],
        "chatPreferences": ["ChatPreferences.Title", "chat settings per chat 会话 對話 格式"],
        "revokedMessages": ["Revoked.Title", "revoked history 撤回 历史 歷史"],
        "diagnostics": ["Diagnostics.Title", "diagnostics speed performance 速度 性能 诊断 診斷"],
        "filterNotifications": ["Notifications.ContentFilter", "notification filter 通知 过滤 過濾"],
    ]

    public static func matches(query: String, id: String, lang: String) -> Bool {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty, let values = keys[id] else { return false }
        let text = ([id] + values.map { $0.contains(".") ? $0.i18n(lang) : $0 }).joined(separator: " ").lowercased()
        return tokens.allSatisfy { text.contains($0) }
    }
    public static func hasMatches(query: String, lang: String) -> Bool {
        return keys.keys.contains { matches(query: query, id: $0, lang: lang) }
    }
}

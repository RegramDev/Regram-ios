import Foundation

/// Search aliases include the controls inside disclosure pages, so looking for TTF or online
/// presence leads to a usable destination even when the parent row has a different title.
public enum RGProSearchIndex {
    public static let keys: [String: [String]] = [
        "sttSettings": ["RG.STTSettings", "speech transcription whisper openai model voice audio round video 语音 转写 识别 圆视频 模型 密钥 音频 語音 辨識"],
        "transcriptionSettings": ["Settings.Category.transcription", "Settings.Transcription.Backend", "speech voice telegram apple 语音 转写 识别"],
        "translationSettings": ["Settings.Category.translation", "translation google microsoft yandex transmart llm 翻译"],
        "llmSettings": ["LLMTranslation.Title", "LLMTranslation.Model", "openai anthropic prompt temperature context 大模型 提示词 温度 上下文"],
        "linkPreviewSettings": ["LinkPreview.Repair", "preview x twitter instagram reddit pixiv tiktok 链接 预览 修复 连结 連結"],
        "messageActionsSettings": ["Settings.Category.messageActions", "DoubleTap.Action", "Settings.ShowMessageId", "Settings.ShowForwardedMessageDate", "menu double tap id forwarded 消息 菜单 双击 时间 转发"],
        "chatListSettings": ["Settings.Category.chatList", "Settings.UnlimitedPinnedChats", "chat list pinned swipe 聊天 列表 无限 置顶 侧滑"],
        "folderSettings": ["Settings.Category.folders", "JoinFolder.Setting", "folders join 分组 加入"],
        "profileSettings": ["Settings.Category.profiles", "profile id registration phone 资料 注册 手机号"],
        "storiesSettings": ["Settings.Category.stories", "stories stealth 动态 快拍"],
        "appearanceSettings": ["Settings.Category.appearance", "appearance tabs bar saturation 外观 界面 底栏 颜色"],
        "mediaSettings": ["Settings.MediaLoading.Title", "MediaMetadata.Setting", "download speed video quality metadata 下载 速度 媒体 信息 播放 画质"],
        "photoSettings": ["Settings.Category.photos", "photo quality image 照片 画质 图片"],
        "stickerSettings": ["Settings.Category.stickers", "sticker emoji size recent 贴纸 表情 最近 大小"],
        "recordingSettings": ["Settings.Category.recording", "recording microphone round camera 录制 麦克风 圆视频"],
        "localGifts": ["Showroom.Title", "LocalGifts.Title", "LocalPhone.Title", "LocalPremium.Title", "LocalRating.Title", "LocalWallet.Title", "local stars gifts purchase rating credit TON Gram wallet card 本地 星币 礼物 购买 评级 低信用度 资料卡"],

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
        "bookmarks": ["Bookmarks.Title", "bookmark tags labels 书签 标签 書籤 標籤"],
        "inputSettings": ["Settings.Category.input", "send input button 发送 输入 按钮"],
        "transferSettings": ["Settings.Category.transfer", "network download upload tcp 网络 传输 下载 上传"],
        "privacySettings": ["Settings.Category.privacy", "phone sensitive 隐私 手机 敏感"],
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

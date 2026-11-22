import RGSettingsUI

/// Categories remain on the Pro home. Their controls share one screen; large collections use
/// native tabs within that screen, and specialised editors remain separate destinations.
struct RGProCategoryLayout {
    let pages: [RGSettingsPage]
    let usesTabs: Bool

    init?(page: RGProSettingsPage) {
        switch page {
        case .messages: self.pages = [.messageActions, .chatList, .folders]
        case .input: self.pages = [.input]
        case .privacy: self.pages = [.privacy, .stories]
        case .translation: self.pages = [.translation]
        case .media: self.pages = [.media, .photos, .stickers, .recording]
        case .appearance: self.pages = [.appearance, .profiles]
        case .network: self.pages = [.transfer]
        case .home, .notifications, .tools: return nil
        }
        self.usesTabs = page == .messages || page == .media
    }

    static let inlinedLinks: Set<String> = [
        "messageActionsSettings", "chatListSettings", "folderSettings", "inputSettings",
        "appearanceSettings", "profileSettings", "storiesSettings", "privacySettings",
        "translationSettings", "mediaSettings", "photoSettings", "stickerSettings",
        "recordingSettings", "transferSettings"
    ]
}

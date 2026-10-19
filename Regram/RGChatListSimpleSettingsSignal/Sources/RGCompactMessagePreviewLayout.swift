import RGSimpleSettings
import CoreGraphics
import Display

enum RGCompactMessagePreviewLayout {
    static func isEnabled() -> Bool {
        maximumMessageLines() == 1
    }

    // MARK: Regram — the selection counts message-body lines, not title/author rows.
    static func maximumMessageLines() -> Int {
        switch RGSimpleSettings.ChatListLines(rawValue: RGSimpleSettings.shared.chatListLines) ?? .two {
        case .one: return 1
        case .two: return 2
        }
    }

    static func minimumRowHeight(titleHeight: CGFloat, authorHeight: CGFloat, bodyHeight: CGFloat, sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasTags: Bool) -> CGFloat {
        let hasAuthor = authorHeight > 0
        let bodyBottom = titleHeight - 2.0 + (hasAuthor ? authorHeight - 3.0 : 0.0)
            + textBlockOffset(sizeFactor: sizeFactor, compactMessagePreview: compactMessagePreview, compactChatList: compactChatList, hasAuthorLine: hasAuthor) + bodyHeight
        let titleBottom = titleHeight + textVerticalOffset(sizeFactor: sizeFactor, compactMessagePreview: compactMessagePreview, compactChatList: compactChatList, hasAuthorLine: hasAuthor)
        let tagsHeight = hasTags ? floorToScreenPixels(22.0 * sizeFactor) : 0.0
        return floorToScreenPixels(8.0 * sizeFactor) + max(titleBottom, bodyBottom) + tagsHeight + max(6.0, 8.0 * sizeFactor)
    }

    static func avatarScaleDivisor(compactChatList: Bool, compactMessagePreview: Bool) -> CGFloat {
        compactChatList ? 1.5 : (compactMessagePreview ? 1.1 : 1.0)
    }

    static func forumTopicIconYOffset(compactMessagePreview: Bool) -> CGFloat {
        compactMessagePreview ? 8.0 : 0.0
    }

    static func badgeOffset(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList else {
            return 0.0
        }

        let sizeRange: CGFloat = 0.5
        let maxLift: CGFloat = 16.0
        let maxDownshift: CGFloat = 24.0
        let sizeDelta = sizeFactor - 1.0
        let lift: CGFloat
        if sizeDelta >= 0.0 {
            let sizeGrow = min(sizeRange, sizeDelta)
            let sizeGrowFactor = sizeGrow / sizeRange
            lift = maxLift * sizeGrowFactor * sizeGrowFactor * (3.0 - 2.0 * sizeGrowFactor)
        } else {
            let sizeShrink = min(sizeRange, -sizeDelta)
            let sizeShrinkFactor = sizeShrink / sizeRange
            let downshift = maxDownshift * sizeShrinkFactor * sizeShrinkFactor * (3.0 - 2.0 * sizeShrinkFactor)
            lift = -downshift
        }

        return floorToScreenPixels(lift)
    }

    static func textVerticalOffset(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasAuthorLine: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList && !hasAuthorLine else {
            return 0.0
        }
        return floorToScreenPixels(6.0 * sizeFactor)
    }

    static func titleTextSpacing(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasAuthorLine: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList && !hasAuthorLine else {
            return 0.0
        }
        return floorToScreenPixels(6.0 * sizeFactor)
    }

    static func textBlockOffset(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasAuthorLine: Bool) -> CGFloat {
        textVerticalOffset(sizeFactor: sizeFactor, compactMessagePreview: compactMessagePreview, compactChatList: compactChatList, hasAuthorLine: hasAuthorLine)
        + titleTextSpacing(sizeFactor: sizeFactor, compactMessagePreview: compactMessagePreview, compactChatList: compactChatList, hasAuthorLine: hasAuthorLine)
    }
}

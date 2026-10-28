// MARK: Regram
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import RGSimpleSettings

public extension EnginePeer {
    var rgCanSetGroupRemark: Bool {
        switch self {
        case .legacyGroup: return true
        case .channel: return true
        default: return false
        }
    }

    var rgRemarkLocalizationPrefix: String {
        if case let .channel(channel) = self, case .broadcast = channel.info { return "ChannelRemark" }
        return "GroupRemark"
    }

    func rgGroupDisplayTitle(accountId: Int64, strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> String {
        if rgCanSetGroupRemark, let name = RGGroupRemarks.shared.name(accountId: accountId, peerId: id.toInt64()) {
            return name
        }
        return displayTitle(strings: strings, displayOrder: displayOrder)
    }
}

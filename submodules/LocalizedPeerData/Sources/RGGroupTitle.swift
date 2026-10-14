// MARK: Regram
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import RGSimpleSettings

public extension EnginePeer {
    var rgCanSetGroupRemark: Bool {
        switch self {
        case .legacyGroup: return true
        case let .channel(channel):
            if case .group = channel.info { return true }
            return false
        default: return false
        }
    }

    func rgGroupDisplayTitle(accountId: Int64, strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> String {
        if rgCanSetGroupRemark, let name = RGGroupRemarks.shared.name(accountId: accountId, peerId: id.toInt64()) {
            return name
        }
        return displayTitle(strings: strings, displayOrder: displayOrder)
    }
}

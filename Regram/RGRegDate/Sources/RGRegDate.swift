import Foundation
import SwiftSignalKit
import TelegramPresentationData

import RGStrings
import RGRegDateScheme
import AccountContext
import RGSimpleSettings

public enum RegDateError {
    case generic
}

// MARK: Regram — estimate registration dates on-device.
// The inherited remote endpoint required an Apple DeviceCheck identity that re-signed builds
// cannot supply. Local interpolation avoids that dependency and sending opened profile IDs
// to a third party. See `rgEstimateRegDate`.
public func getRegDate(context: AccountContext, peerId: Int64) -> Signal<RegDate?, NoError> {
    guard RGSimpleSettings.shared.showRegDate else {
        return .single(nil)
    }

    // Preserve valid estimates cached by earlier Regram versions.
    if let regDateData = RGSimpleSettings.shared.regDateCache[String(peerId)],
       let regDate = try? JSONDecoder().decode(RegDate.self, from: regDateData),
       regDate.validUntil == 0 || regDate.validUntil > Int64(Date().timeIntervalSince1970) {
        return .single(regDate)
    }

    return .single(rgEstimateRegDate(userId: peerId))
}

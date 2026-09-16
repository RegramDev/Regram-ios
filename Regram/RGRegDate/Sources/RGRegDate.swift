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

// MARK: Regram — resolved on-device instead of over the network.
//
// This used to call Swiftgram's `/v0/regdate/<id>` endpoint, authenticated with an Apple DeviceCheck
// token. That can never succeed here: a resigned sideloaded build has no DeviceCheck key registered
// under its team, so `DCDevice.generateToken` fails, and the endpoint answers 401 to anything but
// Swiftgram's own app. The failure was also silent — the old `.start(next:)` had no error handler, so
// when the token signal errored nothing was ever emitted and the profile row simply never appeared.
//
// The endpoint returned an interpolated range anyway (`RegDate.from`/`to`, rendered as its midpoint),
// so computing it locally loses no accuracy while removing the network round trip, the failure mode,
// and the leak of every opened profile's id to a third party. See `rgEstimateRegDate`.
public func getRegDate(context: AccountContext, peerId: Int64) -> Signal<RegDate?, NoError> {
    guard RGSimpleSettings.shared.showRegDate else {
        return .single(nil)
    }

    // Values cached while running a build that could still reach the API are preferred: they came
    // from Swiftgram's own dataset, which may be better than the public one baked in here.
    if let regDateData = RGSimpleSettings.shared.regDateCache[String(peerId)],
       let regDate = try? JSONDecoder().decode(RegDate.self, from: regDateData),
       regDate.validUntil == 0 || regDate.validUntil > Int64(Date().timeIntervalSince1970) {
        return .single(regDate)
    }

    return .single(rgEstimateRegDate(userId: peerId))
}

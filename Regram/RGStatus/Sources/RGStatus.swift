import Foundation
import SwiftSignalKit
import TelegramCore

public struct RGStatus: Equatable, Codable {
    /// Lowest value that unlocks the Pro feature set. Every gate in the app tests `status > 1`.
    public static let proStatus: Int64 = 2

    public var status: Int64

    public static var `default`: RGStatus {
        return RGStatus(status: RGStatus.proStatus)
    }

    public init(status: Int64) {
        // This build unlocks Pro locally instead of resolving entitlement through the App Store,
        // so never let a lower value (default, reset, or a server response) take Pro away.
        self.status = max(status, RGStatus.proStatus)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.status = max(try container.decodeIfPresent(Int64.self, forKey: "status") ?? RGStatus.proStatus, RGStatus.proStatus)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encodeIfPresent(self.status, forKey: "status")
    }
}

public func updateRGStatusInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (RGStatus) -> RGStatus) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.rgStatus, { entry in
            let currentSettings: RGStatus
            if let entry = entry?.get(RGStatus.self) {
                currentSettings = entry
            } else {
                currentSettings = RGStatus.default
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}

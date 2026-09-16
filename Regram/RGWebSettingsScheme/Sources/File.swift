import Foundation

public struct RGWebSettings: Codable, Equatable {
    public let global: RGGlobalSettings
    public let user: RGUserSettings
    
    public static var defaultValue: RGWebSettings {
        return RGWebSettings(global: RGGlobalSettings(ytPip: true, qrLogin: true, storiesAvailable: false, canViewMessages: true, canEditSettings: false, canShowTelescope: false, announcementsData: nil, regdateFormat: "month", forceReasons: [], unforceReasons: [], paymentsEnabled: true, duckyAppIconAvailable: true, canGrant: false, proSupportUrl: nil, nyAvailable: false), user: RGUserSettings(contentReasons: [], canSendTelescope: false, canBuyInBeta: true))
    }
}

public struct RGGlobalSettings: Codable, Equatable {
    public let ytPip: Bool
    public let qrLogin: Bool
    public let storiesAvailable: Bool
    public let canViewMessages: Bool
    public let canEditSettings: Bool
    public let canShowTelescope: Bool
    public let announcementsData: String?
    public let regdateFormat: String
    public let forceReasons: [Int64]
    public let unforceReasons: [Int64]
    public let paymentsEnabled: Bool
    public let duckyAppIconAvailable: Bool
    public let canGrant: Bool
    public let proSupportUrl: String?
    public let nyAvailable: Bool
}

public struct RGUserSettings: Codable, Equatable {
    public let contentReasons: [String]
    public let canSendTelescope: Bool
    public let canBuyInBeta: Bool
}


public extension RGUserSettings {
    func expandedContentReasons() -> [String] {
        return contentReasons.compactMap { base64String in
            guard let data = Data(base64Encoded: base64String),
                  let decodedString = String(data: data, encoding: .utf8) else {
                return nil
            }
            return decodedString
        }
    }
}

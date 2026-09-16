import Foundation

public struct RGGHSettings: Codable, Equatable {
    public let announcementsData: String?
    
    public static var defaultValue: RGGHSettings {
        return RGGHSettings(announcementsData: nil)
    }
}
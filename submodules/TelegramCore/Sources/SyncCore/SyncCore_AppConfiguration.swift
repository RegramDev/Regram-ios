import Foundation
import Postbox
import RGWebSettingsScheme
import RGGHSettingsScheme

public struct AppConfiguration: Codable, Equatable {
    // MARK: Regram
    public var rgWebSettings: RGWebSettings
    public var rgGHSettings: RGGHSettings
    
    public var data: JSON?
    public var hash: Int32
    
    public static var defaultValue: AppConfiguration {
        return AppConfiguration(rgWebSettings: RGWebSettings.defaultValue, rgGHSettings: RGGHSettings.defaultValue, data: nil, hash: 0)
    }
    
    init(rgWebSettings: RGWebSettings, rgGHSettings: RGGHSettings, data: JSON?, hash: Int32) {
        self.rgWebSettings = rgWebSettings
        self.rgGHSettings = rgGHSettings
        self.data = data
        self.hash = hash
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        self.rgWebSettings = (try container.decodeIfPresent(RGWebSettings.self, forKey: "sg")) ?? RGWebSettings.defaultValue
        self.rgGHSettings = (try container.decodeIfPresent(RGGHSettings.self, forKey: "sggh")) ?? RGGHSettings.defaultValue
        self.data = try container.decodeIfPresent(JSON.self, forKey: "data")
        self.hash = (try container.decodeIfPresent(Int32.self, forKey: "storedHash")) ?? 0
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        
        try container.encode(self.rgWebSettings, forKey: "sg")
        try container.encode(self.rgGHSettings, forKey: "sggh")
        try container.encodeIfPresent(self.data, forKey: "data")
        try container.encode(self.hash, forKey: "storedHash")
    }
}

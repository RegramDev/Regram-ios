import Foundation

public struct RGChatPreferences: Codable, Equatable {
    public var formatting: String?
    public var panguSpacing: Bool?
    /// Nil inherits the account's automatic ad filter; false disables it for this channel only.
    public var adFiltering: Bool?
    public init(formatting: String? = nil, panguSpacing: Bool? = nil, adFiltering: Bool? = nil) {
        self.formatting = formatting; self.panguSpacing = panguSpacing; self.adFiltering = adFiltering
    }
    public var isEmpty: Bool { self.formatting == nil && self.panguSpacing == nil && self.adFiltering == nil }
    public static func key(accountId: Int64, peerId: Int64) -> String { "\(accountId):\(peerId)" }
}

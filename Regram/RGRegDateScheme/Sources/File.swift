import Foundation

public struct RegDate: Codable {
    public let from: Int64
    public let to: Int64
    public let validUntil: Int64

    // MARK: Regram — the synthesized memberwise init of a public struct is internal, so it cannot be
    // used from the module that now derives this value locally (see rgEstimateRegDate).
    public init(from: Int64, to: Int64, validUntil: Int64) {
        self.from = from
        self.to = to
        self.validUntil = validUntil
    }
}

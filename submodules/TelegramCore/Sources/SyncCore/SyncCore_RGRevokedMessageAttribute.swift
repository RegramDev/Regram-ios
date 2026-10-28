import Foundation
import Postbox

// MARK: Regram — marks a message the sender revoked (recalled) that anti-revoke kept locally.
//
// The server sends a delete; when anti-revoke is on we skip the delete and instead attach this
// attribute so the UI can show a "deleted" indicator. It carries no data — its presence is the flag.
public class RGRevokedMessageAttribute: MessageAttribute {
    public enum Reason: Int32 { case revoked = 0, unavailable = 1 }
    public let date: Int32
    public let reason: Reason

    public init(date: Int32, reason: Reason = .revoked) {
        self.date = date
        self.reason = reason
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
        self.reason = Reason(rawValue: decoder.decodeInt32ForKey("r", orElse: 0)) ?? .revoked
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
        encoder.encodeInt32(self.reason.rawValue, forKey: "r")
    }
}

public extension Message {
    var rgIsRevoked: Bool {
        for attribute in self.attributes {
            if let attribute = attribute as? RGRevokedMessageAttribute {
                return attribute.reason == .revoked
            }
        }
        return false
    }
}

public extension EngineMessage {
    var rgIsRevoked: Bool {
        for attribute in self.attributes {
            if let attribute = attribute as? RGRevokedMessageAttribute {
                return attribute.reason == .revoked
            }
        }
        return false
    }
}

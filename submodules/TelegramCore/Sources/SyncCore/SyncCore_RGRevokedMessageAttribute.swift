import Foundation
import Postbox

// MARK: Regram — marks a message the sender revoked (recalled) that anti-revoke kept locally.
//
// The server sends a delete; when anti-revoke is on we skip the delete and instead attach this
// attribute so the UI can show a "deleted" indicator. It carries no data — its presence is the flag.
public class RGRevokedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    var rgIsRevoked: Bool {
        for attribute in self.attributes {
            if attribute is RGRevokedMessageAttribute {
                return true
            }
        }
        return false
    }
}

public extension EngineMessage {
    var rgIsRevoked: Bool {
        for attribute in self.attributes {
            if attribute is RGRevokedMessageAttribute {
                return true
            }
        }
        return false
    }
}

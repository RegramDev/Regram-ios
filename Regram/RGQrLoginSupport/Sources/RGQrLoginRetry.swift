// MARK: Regram — Nagram retries cold connection failures instead of leaving an empty plate.
import Foundation

public enum RGQrLoginRetry {
    public static func delay(forRPC reason: String) -> TimeInterval? {
        switch reason {
        case "API_ID_INVALID", "API_ID_PUBLISHED_FLOOD", "API_HASH_INVALID": return nil
        default: return 3.0
        }
    }
}

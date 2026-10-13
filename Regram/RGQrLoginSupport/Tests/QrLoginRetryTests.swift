import Foundation

@main struct QrLoginRetryTests {
    static func main() {
        for reason in ["CONNECTION_NOT_INITED", "CONNECTION_LAYER_INVALID", "AUTH_RESTART", "AUTH_TOKEN_EXPIRED", "INTERNAL_SERVER_ERROR"] {
            assert(RGQrLoginRetry.delay(forRPC: reason) == 3.0)
        }
        for reason in ["API_ID_INVALID", "API_ID_PUBLISHED_FLOOD", "API_HASH_INVALID"] {
            assert(RGQrLoginRetry.delay(forRPC: reason) == nil)
        }
        print("QR retry checks passed: cold connections and expired requests retry; invalid application credentials stop.")
    }
}

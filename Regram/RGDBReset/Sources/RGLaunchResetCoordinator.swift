// MARK: Regram — keep destructive startup requests pending until a scene can show confirmation.
import Foundation

public final class RGLaunchResetCoordinator {
    public enum Request: String {
        case fullWipe = "rg_full_wipe"
        case database = "rg_db_hard_reset"
    }
    public let request: Request?
    private var didPresent = false

    public init(defaults: UserDefaults = .standard) {
        request = [Request.fullWipe, .database].first {
            defaults.object(forKey: $0.rawValue) as? Bool == true
        }
    }

    public func claimPresentation(sceneConnected: Bool, active: Bool) -> Request? {
        guard sceneConnected, active, !didPresent, let request else { return nil }
        didPresent = true
        return request
    }

    public static func resolve(_ request: Request, defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: request.rawValue)
        defaults.removeObject(forKey: "Regram.Reset.Language")
        defaults.synchronize()
    }
}

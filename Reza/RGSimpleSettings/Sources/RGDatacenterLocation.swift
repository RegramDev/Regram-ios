// MARK: Regram — conventional Telegram DC regions; these labels are not geolocation of the user.
import Foundation

public enum RGDatacenterLocation {
    public static func name(_ id: Int) -> String? {
        switch id {
        case 1, 3: return "Miami"
        case 2, 4: return "Amsterdam"
        case 5: return "Singapore"
        default: return nil
        }
    }
    public static func title(_ id: Int) -> String {
        "DC\(id)" + (name(id).map { " · " + $0 } ?? "")
    }
}

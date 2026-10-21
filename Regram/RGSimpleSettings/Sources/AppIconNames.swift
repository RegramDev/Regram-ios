import Foundation

// MARK: Regram
public enum RGAppIconNames {
    /// Retired Regram artwork uses the current default icon.
    public static func canonicalName(_ name: String?) -> String? {
        name == "RGAnime" ? "RGDefault" : name
    }
}

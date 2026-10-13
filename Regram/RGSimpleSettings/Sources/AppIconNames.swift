import Foundation

// MARK: Regram
public enum RGAppIconNames {
    public static let renamedSuffixes = [
        "Default", "Black", "Legacy", "Inverted", "White", "Night", "Sky", "Titanium",
        "Neon", "NeonBlue", "Glass", "Sparkling", "Beta", "Pro", "Gold", "Ducky", "Day"
    ]

    /// iOS retains the old alternate-icon identifier across an application update.
    public static func canonicalName(_ name: String?) -> String? {
        guard let name, name.hasPrefix("SG") else {
            return name
        }
        let suffix = String(name.dropFirst(2))
        return renamedSuffixes.contains(suffix) ? "RG" + suffix : name
    }
}

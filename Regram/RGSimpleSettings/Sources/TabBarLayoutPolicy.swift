// MARK: Regram — shared geometry for the real tab bar and its settings preview.
import Foundation

public enum RGTabBarLayoutPolicy {
    public static let settingsChanged = Notification.Name("Regram.TabBarLayoutChanged")
    public static let minimumPercent: Int32 = 50
    public static let maximumPercent: Int32 = 100
    public static let maximumWidth: Double = 500.0
    public static let minimumItemWidth: Double = 44.0

    /// Zero balances content fit with comfortable spacing; explicit widths use the supported bar width.
    public static func normalizedPercent(_ value: Int32) -> Int32 {
        return value <= 0 ? 0 : min(maximumPercent, max(minimumPercent, value))
    }

    public static func migratedPercent(legacyWide: Bool) -> Int32 {
        return legacyWide ? maximumPercent : 0
    }

    public static func width(containerWidth: Double, itemCount: Int, percent: Int32, searchButtonWidth: Double = 0.0, searchActive: Bool = false, naturalItemWidths: [Double]? = nil) -> Double {
        guard containerWidth.isFinite, containerWidth > 0.0, itemCount > 0 else { return 0.0 }
        let availableWidth = min(maximumWidth, containerWidth)
        if searchActive { return availableWidth }
        let normalized = normalizedPercent(percent)
        let reservedSearchWidth = searchButtonWidth.isFinite ? max(0.0, searchButtonWidth) : 0.0
        let requestedWidth: Double
        if normalized == 0 {
            let widths = naturalItemWidths?.count == itemCount ? naturalItemWidths! : Array(repeating: 64.0, count: itemCount)
            // Leave breathing room for the native selection lens and avoid squeezing short labels.
            let comfortableItemWidth = max(88.0, widths.filter(\.isFinite).max() ?? 64.0)
            let contentWidth = Double(itemCount) * comfortableItemWidth + 8.0 + reservedSearchWidth
            let comfortableBarWidth = min(320.0, availableWidth * 0.9)
            requestedWidth = max(contentWidth, comfortableBarWidth)
        } else {
            requestedWidth = availableWidth * Double(normalized) / 100.0
        }
        // Reserve a separate button only when one actually exists. Keep every tab tappable.
        let minimumWidth = min(availableWidth, Double(itemCount) * minimumItemWidth + 8.0 + reservedSearchWidth)
        return min(availableWidth, max(minimumWidth, requestedWidth))
    }

    public static func itemWidths(availableWidth: Double, naturalWidths: [Double]) -> [Double] {
        guard !naturalWidths.isEmpty else { return [] }
        let available = availableWidth.isFinite ? max(0.0, availableWidth) : 0.0
        let equalWidth = available / Double(naturalWidths.count)
        let natural = naturalWidths.map { $0.isFinite ? max(0.0, $0) : 0.0 }
        if natural.allSatisfy({ $0 <= equalWidth }) { return Array(repeating: equalWidth, count: natural.count) }
        let base = min(minimumItemWidth, equalWidth)
        let extra = max(0.0, available - base * Double(natural.count))
        let weights = natural.map { max(0.0, $0 - base) }
        let totalWeight = weights.reduce(0.0, +)
        guard totalWeight > 0.0 else { return Array(repeating: equalWidth, count: natural.count) }
        return weights.map { base + extra * $0 / totalWeight }
    }
}

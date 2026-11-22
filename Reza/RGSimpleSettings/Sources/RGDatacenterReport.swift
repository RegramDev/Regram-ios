// MARK: Regram — a copied DC report is deliberately limited to five average latencies.
import Foundation

public enum RGDatacenterReport {
    public static func averages(_ results: [Int: RGDatacenterStatistics]) -> String {
        return (1...5).map { dc in
            let value = results[dc]?.average.map { String(format: "%.0f ms", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "—"
            return "DC\(dc): \(value)"
        }.joined(separator: "\n")
    }
}

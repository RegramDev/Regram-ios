import Foundation

@main enum DatacenterReportTests {
    static func main() {
        precondition(RGDatacenterReport.averages([:]) == "DC1: —\nDC2: —\nDC3: —\nDC4: —\nDC5: —")
        var a = RGDatacenterStatistics(); a.samples = [10, 20, 30]; a.connectionMilliseconds = 1000; a.failures = 1
        var b = RGDatacenterStatistics(); b.samples = [45, 55]; b.failures = 1
        var failed = RGDatacenterStatistics(); failed.failures = 3; failed.timeouts = 3
        let report = RGDatacenterReport.averages([1: a, 3: b, 4: failed, 8: a])
        precondition(report == "DC1: 20 ms\nDC2: —\nDC3: 50 ms\nDC4: —\nDC5: —")
        precondition(report.components(separatedBy: "\n").count == 5)
        print("DC copied report contains exactly DC1–DC5 averages, excludes initial connection time and does not turn failures into zero ping.")
    }
}

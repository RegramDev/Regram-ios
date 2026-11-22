#!/usr/bin/env python3
"""Measure reviewed-only startup with synthetic records; no real account data or model calls."""
import argparse
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--sources', type=Path, default=root / 'Reza/RGAdFilter/Sources')
args = parser.parse_args()
main = r'''
import Foundation
@main enum Checks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = RGAdSampleStore(accountDirectory: root), encoder = JSONEncoder()
        let source = String(repeating: "这是一条用于验证读取成本的合成样本，不包含真实账号或频道消息。\n", count: 20)
        var reviewed = Set<String>()
        for index in 0..<2020 {
            var sample = try seed.draft(input: RGAdInput(text: source + String(index), peerId: 9), messageKey: String(index), mediaKinds: [], mediaIdentity: "")
            let range = RGAdRange(0, sample.input.text.utf16.count)
            sample.spans = [RGAdSpan(range, .ad)]
            sample.detection = RGAdDetection(recordedAt: 1000, policyRevision: 1, removedRanges: [range], removedButtonIds: [], hidMessage: true)
            if index < 20 { sample.reviewedAt = 1000; reviewed.insert(sample.id) }
            try encoder.encode(sample).write(to: seed.directory.appendingPathComponent(sample.id + ".json"), options: .atomic)
        }
        var times: [Double] = []
        for _ in 0..<4 {
            let store = RGAdSampleStore(accountDirectory: root), started = ProcessInfo.processInfo.systemUptime
            let records = try store.load(reviewedOnly: true)
            times.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            precondition(Set(records.map(\.id)) == reviewed)
        }
        let report: [String: Any] = ["records": 2020, "reviewed": 20, "firstLoadMilliseconds": times[0], "reopenedMilliseconds": Array(times.dropFirst()), "sameReviewedRecords": true]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-ad-store-latency-') as folder:
    folder = Path(folder)
    (folder / 'Main.swift').write_text(main)
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', *map(str, sorted(args.sources.glob('*.swift'))), str(folder / 'Main.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=180)

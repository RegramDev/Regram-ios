// MARK: Regram — a small, credential-free schema shared by the app and Widget extension.
import Foundation
import ActivityKit

@available(iOS 16.1, *)
public struct RGUpdateActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let phase: String
        public let label: String
        public let action: String
        public let staleLabel: String
        public let downloaded: Int64
        public let total: Int64
        public var fraction: Double { min(1, max(0, Double(downloaded) / Double(max(1, total)))) }
        public var isDeterminate: Bool { phase == "downloading" }
        public init(phase: String, label: String, action: String, staleLabel: String, downloaded: Int64, total: Int64) {
            self.phase = phase; self.label = label; self.action = action; self.staleLabel = staleLabel
            self.downloaded = max(0, min(downloaded, total)); self.total = max(0, total)
        }
    }
    public let build: Int64
    public let version: String
    public let title: String
    public let updateURL: URL
    public init(build: Int64, version: String, title: String, updateURL: URL) {
        self.build = build; self.version = version; self.title = title; self.updateURL = updateURL
    }
}

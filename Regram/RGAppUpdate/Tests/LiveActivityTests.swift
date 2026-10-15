import Foundation
import UIKit
import ActivityKit
import RGUpdateActivity

@main struct LiveActivityTests {
    @MainActor static func drain() async { for _ in 0..<30 { await Task.yield() } }
    @MainActor static func main() async throws {
        let release = RGUpdateRelease(version: "13.0", build: 34613, downloadURL: URL(string: "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34613/Regram-13.0-b34613.ipa")!, sha256: String(repeating: "a", count: 64), size: 1000, notes: "unused")
        let coordinator = RGUpdateLiveActivity()
        func snapshot(_ phase: String, _ bytes: Int64 = 0, _ mayStart: Bool = true) -> RGUpdateLiveActivity.Snapshot { .init(release: release, phase: phase, labelKey: phase, downloaded: bytes, language: "en", mayStart: mayStart) }
        coordinator.submit(snapshot("downloading", 100)); await drain()
        let activity = Activity<RGUpdateActivityAttributes>.activities.first!
        assert(activity.attributes.build == release.build && activity.state.fraction == 0.1)
        assert(activity.attributes.updateURL.host == "rg" && activity.attributes.updateURL.path == "/settings")
        assert(activity.staleDate != nil && ActivityFixture.requests == 1)
        coordinator.submit(snapshot("downloading", 105)); await drain()
        assert(activity.state.downloaded == 100, "Throttle insignificant progress")
        coordinator.submit(snapshot("downloading", 300)); await drain()
        assert(activity.state.fraction == 0.3 && ActivityFixture.requests == 1)
        coordinator.submit(snapshot("signing", 1000)); await drain()
        assert(activity.state.phase == "signing" && !activity.state.isDeterminate)
        coordinator.submit(snapshot("ready", 1000)); await drain()
        assert(activity.staleDate == nil && activity.state.phase == "ready")
        coordinator.submit(nil); await drain()
        assert(Activity<RGUpdateActivityAttributes>.activities.isEmpty)
        UIApplication.shared.applicationState = .background
        coordinator.submit(snapshot("downloading")); await drain()
        assert(Activity<RGUpdateActivityAttributes>.activities.isEmpty, "Background cannot create local activity")
        UIApplication.shared.applicationState = .active
        ActivityFixture.enabled = false
        coordinator.submit(snapshot("downloading")); await drain()
        assert(Activity<RGUpdateActivityAttributes>.activities.isEmpty, "System permission is respected")
        ActivityFixture.enabled = true
        coordinator.submit(snapshot("ready", 1000, false)); await drain()
        assert(Activity<RGUpdateActivityAttributes>.activities.isEmpty, "Restored cache does not start an unsolicited task")
        coordinator.submit(snapshot("downloading", 100)); await drain()
        ActivityFixture.suspendUpdate = true
        coordinator.submit(snapshot("signing", 1000)); await drain()
        assert(ActivityFixture.pending != nil)
        coordinator.submit(nil)
        ActivityFixture.suspendUpdate = false
        coordinator.submit(snapshot("downloading", 200)); await drain()
        let resumed = ActivityFixture.pending; ActivityFixture.pending = nil; resumed?.resume(); await drain()
        assert(Activity<RGUpdateActivityAttributes>.activities.count == 1)
        assert(Activity<RGUpdateActivityAttributes>.activities.first!.state.phase == "downloading", "Cancelled old update cannot replace the new task")
        await coordinator.end()
        assert(Activity<RGUpdateActivityAttributes>.activities.isEmpty)
        for bytes in [Int64.min, -1, 0, 50, 100, Int64.max] {
            let state = RGUpdateActivityAttributes.ContentState(phase: "downloading", label: "fixture", action: "open", staleLabel: "paused", downloaded: bytes, total: 100)
            assert(state.fraction >= 0 && state.fraction <= 1)
            let data = try JSONEncoder().encode(state)
            assert(data.count < 4096)
            let decoded = try JSONDecoder().decode(RGUpdateActivityAttributes.ContentState.self, from: data)
            assert(decoded == state)
        }
        print("Live Activity: progress/clamping/schema roundtrip, throttling, phase changes, foreground/permission gating, restore, cancellation, late async updates and cleanup passed.")
    }
}

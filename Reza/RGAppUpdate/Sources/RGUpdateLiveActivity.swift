// MARK: Regram — local ActivityKit updates; no account, certificate, key or push service is used.
import Foundation
import UIKit
import ActivityKit
import RGUpdateActivity
import RGStrings

@MainActor final class RGUpdateLiveActivity {
    struct Snapshot: Equatable {
        let release: RGUpdateRelease
        let phase: String
        let labelKey: String
        let downloaded: Int64
        let language: String
        let mayStart: Bool
    }
    private var pending: Snapshot?
    private var worker: Task<Void, Never>?
    private var generation = UUID()
    private var lastBuild: Int64?
    private var lastPhase = ""
    private var lastPercent = -1
    private var lastUpdate = Date.distantPast
    private var rejectedBuild: Int64?

    func submit(_ snapshot: Snapshot?) {
        guard #available(iOS 16.1, *) else { return }
        guard let snapshot else {
            reset()
            let old = Activity<RGUpdateActivityAttributes>.activities
            Task { for activity in old { await finish(activity) } }
            return
        }
        let percent = Int(Double(snapshot.downloaded) / Double(max(1, snapshot.release.size)) * 100)
        if snapshot.phase == "downloading", snapshot.release.build == lastBuild, snapshot.phase == lastPhase,
           abs(percent - lastPercent) < 2, Date().timeIntervalSince(lastUpdate) < 1 { return }
        pending = snapshot
        guard worker == nil else { return }
        let token = generation
        worker = Task {
            while let snapshot = pending, token == generation {
                pending = nil
                await apply(snapshot, generation: token)
            }
            if token == generation { worker = nil }
        }
    }

    @available(iOS 16.1, *)
    private func apply(_ snapshot: Snapshot, generation token: UUID) async {
        let release = snapshot.release
        let updateURL = RGUpdateSettingsLink.current
        let activities = Activity<RGUpdateActivityAttributes>.activities
        // Retire persisted activities from versions that chose a web/wallet URL protocol.
        for activity in activities where activity.attributes.build != release.build || activity.attributes.updateURL != updateURL { await finish(activity) }
        guard token == generation, !Task.isCancelled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let labels = snapshot.language
        let state = RGUpdateActivityAttributes.ContentState(phase: snapshot.phase, label: snapshot.labelKey.i18n(labels), action: "AppUpdate.ActivityOpen".i18n(labels), staleLabel: "AppUpdate.ActivityStale".i18n(labels), downloaded: snapshot.downloaded, total: release.size)
        var activity = activities.first { $0.attributes.build == release.build && $0.attributes.updateURL == updateURL && $0.activityState != .ended && $0.activityState != .dismissed }
        if activity == nil, snapshot.mayStart, UIApplication.shared.applicationState == .active, rejectedBuild != release.build {
            let attributes = RGUpdateActivityAttributes(build: release.build, version: release.version, title: "AppUpdate.Title".i18n(labels), updateURL: updateURL)
            do {
                if #available(iOS 16.2, *) { activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: staleDate(snapshot)), pushType: nil) }
                else { activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil) }
            } catch { rejectedBuild = release.build; return }
        }
        guard let activity else { return }
        if #available(iOS 16.2, *) { await activity.update(ActivityContent(state: state, staleDate: staleDate(snapshot))) }
        else { await activity.update(using: state) }
        guard token == generation, !Task.isCancelled else { return }
        lastBuild = release.build; lastPhase = snapshot.phase; lastPercent = Int(state.fraction * 100); lastUpdate = Date()
    }

    private func staleDate(_ snapshot: Snapshot) -> Date? {
        ["ready", "downloaded"].contains(snapshot.phase) ? nil : Date().addingTimeInterval(90)
    }

    private func reset() {
        generation = UUID(); pending = nil; worker?.cancel(); worker = nil
        lastBuild = nil; lastPhase = ""; lastPercent = -1
        rejectedBuild = nil
    }
    func end() async {
        reset()
        if #available(iOS 16.1, *) { for activity in Activity<RGUpdateActivityAttributes>.activities { await finish(activity) } }
    }
    @available(iOS 16.1, *)
    private func finish(_ activity: Activity<RGUpdateActivityAttributes>) async {
        if #available(iOS 16.2, *) { await activity.end(nil, dismissalPolicy: .immediate) }
        else { await activity.end(dismissalPolicy: .immediate) }
    }
}

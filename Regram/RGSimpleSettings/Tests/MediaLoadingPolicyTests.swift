// MARK: Regram — deterministic regression checks for cancellation races and scheduling.
import Foundation

@main
private enum MediaLoadingPolicyTests {
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() {
        var retention = RGMediaPreloadRetention<String>()
        let first = retention.deferRemoval("video", now: 10).ticket
        expect(!retention.expire("video", ticket: first, now: 11.49), "Must retain a task throughout the grace window")
        retention.rescue("video")
        let replacement = retention.deferRemoval("video", now: 11).ticket
        expect(!retention.expire("video", ticket: first, now: 12), "An old timer must not cancel a rescued/replaced request")
        expect(retention.expire("video", ticket: replacement, now: 12.5), "The current task must be released at its deadline")

        let oldest = retention.deferRemoval("one", now: 20).ticket
        let _ = retention.deferRemoval("two", now: 20)
        let _ = retention.deferRemoval("three", now: 20)
        let eviction = retention.deferRemoval("four", now: 20)
        expect(eviction.evicted == ["one"] && retention.pending.count == 3, "Rapid scrolling must bound retained work and evict the oldest task")
        expect(!retention.expire("one", ticket: oldest, now: 22), "An evicted task's callback must be harmless")
        let surviving = retention.pending["four"]!
        retention.reset()
        expect(!retention.expire("four", ticket: surviving, now: 22), "Closing the screen/changing network policy must invalidate every pending callback")

        var priorities = RGMediaPriorityState()
        let _ = priorities.updateScreen(owner: 1, visible: ["old-chat"], preload: ["old-next"])
        let _ = priorities.updateScreen(owner: 2, visible: ["current", "current"], preload: ["next", "current"])
        let _ = priorities.updateScreen(owner: 1, visible: [], preload: [])
        expect(priorities.visible == ["current"], "A covered chat must not erase the new chat's priorities")
        expect(!priorities.updateScreen(owner: 2, visible: ["current"], preload: ["next", "current"]), "Equivalent windows must not repeat reconciliation")
        priorities.acquireStreaming("playing")
        priorities.acquireStreaming("playing")
        priorities.releaseStreaming("playing")
        let _ = priorities.updateScreen(owner: 2, visible: [], preload: [])
        expect(priorities.streaming == ["playing"], "A second player/gallery handoff must preserve its own streaming reference")
        expect(priorities.weights(enabled: false).isEmpty, "Disabling the experiment must remove every network priority")
        expect(priorities.weights(enabled: true)["playing"] == 100, "Re-enabling must restore a still-playing resource")
        priorities.releaseStreaming("playing")
        priorities.releaseStreaming("playing")
        expect(priorities.streaming.isEmpty, "The final playback release must restore normal scheduling")

        let candidates = [
            RGMediaFetchCandidate(resourceId: "paused", isUserInitiated: true, isPaused: true),
            RGMediaFetchCandidate(resourceId: "manual", isUserInitiated: true),
            RGMediaFetchCandidate(resourceId: "background"),
            RGMediaFetchCandidate(resourceId: "next", isForegroundPrefetch: true),
            RGMediaFetchCandidate(resourceId: "visible"),
            RGMediaFetchCandidate(resourceId: "visible"),
        ]
        let selected = RGMediaLoadingPolicy.selectedResources(candidates: candidates, visible: ["visible", "visible"], preload: ["next"], streaming: [])
        expect(selected == ["manual", "visible", "next"], "Visible media must advance ahead of background work without starving manual downloads or counting duplicates twice")
        let streaming = RGMediaLoadingPolicy.selectedResources(candidates: candidates, visible: ["visible"], preload: ["next"], streaming: ["direct-stream"])
        expect(streaming == ["manual", "visible"], "Direct playback must defer offscreen automatic work and leave bandwidth headroom")
        let resumed = RGMediaLoadingPolicy.selectedResources(candidates: candidates, visible: [], preload: [], streaming: [])
        expect(resumed.contains("manual") && resumed.contains("background"), "Background work must be eligible again after playback/screen priority ends")
        expect(!resumed.contains("paused"), "A paused download must never be restarted by reconciliation")

        func video(_ id: Int64, distance: Double, visible: Double = 1, eligible: Bool = true, sound: Bool = false, admitted: Bool = false) -> RGInlineVideoCandidate {
            return RGInlineVideoCandidate(id: id, stableId: id, eligible: eligible, visibleFraction: visible, distanceFromCenter: distance, userInitiated: sound, hasSound: sound, alreadyAdmitted: admitted)
        }
        let videos = [video(1, distance: 50), video(2, distance: 0), video(3, distance: 20), video(4, distance: 0, visible: 0)]
        expect(RGMediaLoadingPolicy.selectedInlineVideos(videos, active: true, thermalCritical: false) == [2, 3], "Only two visible center candidates should acquire decoders")
        expect(RGMediaLoadingPolicy.selectedInlineVideos(videos, active: false, thermalCritical: false).isEmpty, "A covered chat must release playback admissions")
        expect(RGMediaLoadingPolicy.selectedInlineVideos(videos, active: true, thermalCritical: true).isEmpty, "Critical thermal pressure must revoke autoplay")
        expect(RGMediaLoadingPolicy.selectedInlineVideos(videos + [video(5, distance: 100, sound: true)], active: true, thermalCritical: false).first == 5, "An audible/user-started video must win over center autoplay")
        expect(RGMediaLoadingPolicy.selectedInlineVideos([video(1, distance: 0), video(2, distance: 0, admitted: true)], active: true, thermalCritical: false, limit: 1) == [2], "Equal candidates must preserve admission and avoid repeated player churn")

        var players = RGInlineVideoRetention<String>()
        expect(players.retain("previous", session: 1, activeInlineCount: 2).isEmpty && players.ids == ["previous"], "Two active decoders may retain one detached player")
        players.take("previous")
        expect(players.ids.isEmpty, "Reattachment must consume the retained entry")
        let _ = players.retain("old", session: 1, activeInlineCount: 2)
        expect(players.retain("new", session: 2, activeInlineCount: 2) == ["old"], "Cross-chat scrolling must cap the pool globally")
        expect(players.end(session: 1).isEmpty && players.ids == ["new"], "Closing an older chat must not evict the current chat's retained player")
        expect(players.prefer("gallery", session: 2) == ["new"], "A gallery handoff must remove a nonpreferred retained player")
        expect(players.retain("other", session: 2, activeInlineCount: 1) == ["other"] && players.ids.isEmpty, "A nonpreferred handoff must not fill the retention pool")
        let _ = players.retain("gallery", session: 2, activeInlineCount: 2)
        expect(players.trim(activeInlineCount: 3) == ["gallery"], "Active inline content and retained content must share the three-holder budget")
        let _ = players.prefer(nil, session: 2)
        let _ = players.retain("last", session: 2, activeInlineCount: 0)
        expect(players.reset() == ["last"] && players.ids.isEmpty, "Memory/background/settings teardown must release every retained player")

        var lanes = RGStreamingAdmissionState()
        let initialLease = lanes.acquire(owner: 1, resources: ["playlist", "360", "720"], userInitiated: false)
        let _ = lanes.acquire(owner: 2, resources: ["next"], userInitiated: false)
        lanes.prefer(owner: 1, session: 10)
        expect(lanes.selectedResources == ["playlist", "360", "720"], "Every quality of the preferred player must pass the remote fragment gate")
        let _ = lanes.acquire(owner: 3, resources: ["gallery"], userInitiated: true)
        expect(lanes.selectedResources == ["gallery"], "Foreground sound playback must defer inline fragment downloads")
        lanes.release(owner: 3)
        expect(lanes.selectedResources.contains("720"), "Deferred quality requests must regain admission after the gallery releases")
        let replacementLease = lanes.acquire(owner: 1, resources: ["replacement"], userInitiated: false)
        lanes.release(owner: 1, generation: initialLease)
        expect(lanes.selectedResources == ["replacement"], "A stale release must not remove a new owner's streaming lease")
        lanes.release(owner: 1, generation: replacementLease)
        expect(lanes.selectedResources == ["next"], "Releasing the preferred owner must restore another active owner")
        lanes.prefer(owner: 2, session: 20)
        lanes.prefer(owner: nil, session: 10)
        expect(lanes.selectedResources == ["next"], "A covered session's preference cleanup must preserve the current session")
        lanes.release(owner: 2)
        expect(lanes.selectedResources.isEmpty, "The final streaming release must reopen the remote lane")

        let verdicts = RGMessageVerdictCache<String, String>(capacity: 2)
        verdicts.store("eligible", for: "edited", version: 1)
        expect(verdicts.value(for: "edited", version: 2) == nil, "An edited message must not reuse an old translation/filter verdict")
        verdicts.store("already translated", for: "edited", version: 2)
        expect(verdicts.value(for: "edited", version: 2) == "already translated", "New translation attributes must replace eligibility on version changes")
        verdicts.store("two", for: "two", version: 1)
        verdicts.store("three", for: "three", version: 1)
        expect(verdicts.value(for: "edited", version: 2) == nil, "Long histories must evict bounded verdicts")

        var translations = RGTranslationWorkState<String>()
        let en = translations.begin(["message", "message"], language: "en", now: 0)
        expect(en.keys == ["message"] && !translations.canSchedule("message", language: "en", now: 2), "An in-flight batch must suppress duplicate messages and repeated scroll submissions")
        translations.reset()
        let ja = translations.begin(["message"], language: "ja", now: 2)
        translations.finish(en.keys, language: "en", generation: en.generation, now: 3)
        expect(!translations.canSchedule("message", language: "ja", now: 3), "A canceled language's late completion must not unlock the new batch")
        translations.finish(ja.keys, language: "ja", generation: ja.generation, now: 3)
        expect(!translations.canSchedule("message", language: "ja", now: 3.5) && translations.canSchedule("message", language: "ja", now: 4), "Incomplete/failed translation must become retryable without a hot resubmit loop")

        #if REGRAM_MEDIA_LOADING_EXPERIMENT
        expect(RGMediaLoadingPolicy.enabledByDefault, "The trial build must enable the experiment by default")
        #else
        expect(!RGMediaLoadingPolicy.enabledByDefault, "Regular builds must retain the existing default")
        #endif
        expect(RGVideoQualityPreference.automatic.selectedQuality(available: [1080, 360, 720]) == nil, "Automatic playback must not silently reduce quality")
        expect(RGVideoQualityPreference.highest.selectedQuality(available: [720, 360, 1080, 720]) == 1080, "Highest preference must use the largest available quality")
        expect(RGVideoQualityPreference.lowest.selectedQuality(available: [720, 360, 1080]) == 360, "Lowest preference must use the smallest available quality")
        expect(RGVideoQualityPreference.lowest.selectedQuality(available: [0, -1, 720, 720]) == nil, "Single/invalid quality sets must retain automatic behavior")
        expect(RGNotificationPolicy.shouldSuppress(markedControl: true, hasText: true, hasAttachments: true, hasSender: true), "Marked read/delete notifications must remain suppressed after polling adds media")
        expect(!RGNotificationPolicy.shouldSuppress(markedControl: false, hasText: false, hasAttachments: true, hasSender: false), "A real attachment-only notification must not be mistaken for empty")
        expect(!RGNotificationPolicy.shouldSuppress(markedControl: false, hasText: true, hasAttachments: false, hasSender: false), "Privacy placeholders and ordinary messages must retain their alert")
        expect(RGNotificationPolicy.shouldSuppress(markedControl: false, hasText: false, hasAttachments: false, hasSender: false), "Unresolved empty notifications must enter the safe fallback")
        expect(!RGNotificationPolicy.shouldRecoverBadge(foreignSession: false, markedControl: true), "The completion handler must not reintroduce a control push's badge")
        expect(!RGNotificationPolicy.shouldRecoverBadge(foreignSession: true, markedControl: false), "Foreign sessions must not overwrite the current badge")
        expect(RGNotificationPolicy.shouldRecoverBadge(foreignSession: false, markedControl: false), "Unresolved genuine pushes may preserve the incoming badge")
        expect(RGNotificationPolicy.maximumStartupAttempts == 3 && RGNotificationPolicy.retryDelay(attempt: 1) + RGNotificationPolicy.retryDelay(attempt: 2) < 1, "Cold startup retries must be bounded within the extension time budget")
        expect(RGNotificationPolicy.processingDeadline > 0 && RGNotificationPolicy.processingDeadline < 30, "The extension must proactively complete within its system time budget")
        expect([0, 7, 8, 23, 24, 39, 41, 55].allSatisfy { !RGNotificationPolicy.isPlausibleEncryptedPayload(byteCount: $0) }, "Truncated headers and unaligned ciphertext must fail safely before decryption")
        expect([40, 56, 72, 4088].allSatisfy { RGNotificationPolicy.isPlausibleEncryptedPayload(byteCount: $0) }, "Complete encrypted payload blocks must remain eligible for decryption")
        print("Media loading policy: prefetch races, playback admission, retained players, fragment owners, versioned verdicts, translation work and build defaults passed")
    }
}

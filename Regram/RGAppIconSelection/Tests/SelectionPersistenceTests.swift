import Foundation

private final class Clock {
    var now: Double = 0
    var events: [(Double, () -> Void)] = []
    func schedule(_ delay: Double, _ body: @escaping () -> Void) { events.append((now + delay, body)) }
    func advance(_ delta: Double) {
        let end = now + delta
        while let index = events.indices.filter({ events[$0].0 <= end }).min(by: { events[$0].0 < events[$1].0 }) {
            let event = events.remove(at: index); now = event.0; event.1()
        }
        now = end
    }
}

private final class Fixture {
    var system: String?
    let clock = Clock()
    let selection: RGAppIconSelectionStore
    var requests: [(String?, UUID, (Bool) -> Void)] = []
    lazy var coordinator = RGAppIconSwitchCoordinator(current: { [unowned self] in
        self.selection.resolvedName(systemName: self.system)
    }, apply: { [unowned self] name, callback in
        let token = self.selection.beginRequest(name, systemName: self.system)
        self.requests.append((name, token, callback))
    }, changed: {}, schedule: { [unowned self] in self.clock.schedule($0, $1) })

    init(_ defaults: UserDefaults, system: String? = nil) {
        self.system = system
        let clock = self.clock
        self.selection = RGAppIconSelectionStore(defaults: defaults, clock: { clock.now })
    }
    func finish(_ index: Int, _ success: Bool) {
        self.selection.finishRequest(self.requests[index].1, succeeded: success)
        self.requests[index].2(success)
    }
}

@main enum SelectionChecks {
    static func main() {
        let suite = "app.regram.icon-selection-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep", forKey: "unrelated-setting")
        let existing = Fixture(defaults, system: "RGGathering")
        precondition(existing.coordinator.currentIconName == "RGGathering")
        precondition(Fixture(defaults).coordinator.currentIconName == "RGGathering", "A valid observed alternate survives a cold nil getter")
        defaults.removeObject(forKey: RGAppIconSelectionStore.key)
        let first = Fixture(defaults)
        first.coordinator.request("RGGathering") { precondition($0) }
        first.finish(0, true)
        let restarted = Fixture(defaults)
        precondition(restarted.coordinator.currentIconName == "RGGathering")
        restarted.coordinator.resume(); restarted.clock.advance(2)
        precondition(restarted.coordinator.currentIconName == "RGGathering")
        restarted.system = "RGGathering"; restarted.coordinator.resume()
        let confirmedRestart = Fixture(defaults)
        precondition(confirmedRestart.coordinator.currentIconName == "RGGathering")
        let prior = defaults.dictionary(forKey: RGAppIconSelectionStore.key)! as NSDictionary
        confirmedRestart.coordinator.request(nil) { precondition(!$0) }
        confirmedRestart.finish(0, false)
        precondition(prior == defaults.dictionary(forKey: RGAppIconSelectionStore.key)! as NSDictionary, "A failed reset cannot overwrite persistence")
        confirmedRestart.coordinator.request(nil) { precondition($0) }
        confirmedRestart.finish(1, true)
        precondition(defaults.dictionary(forKey: RGAppIconSelectionStore.key)?["primary"] as? Bool == true)
        let primaryRestart = Fixture(defaults, system: "RGGathering")
        precondition(primaryRestart.coordinator.currentIconName == nil, "Keep an acknowledged primary while UIKit still reports the old alternate")
        primaryRestart.system = nil; primaryRestart.coordinator.resume()

        let missingCallback = Fixture(defaults)
        var result: Bool?
        missingCallback.coordinator.request("RGGathering") { result = $0 }
        missingCallback.system = "RGGathering"; missingCallback.clock.advance(15)
        precondition(result == true && Fixture(defaults).coordinator.currentIconName == "RGGathering")
        let resetWithoutCallback = Fixture(defaults, system: "RGGathering")
        resetWithoutCallback.coordinator.request(nil) { precondition($0) }
        resetWithoutCallback.system = nil; resetWithoutCallback.clock.advance(15)
        precondition(Fixture(defaults, system: "RGGathering").coordinator.currentIconName == nil)

        let timeout = Fixture(defaults)
        timeout.coordinator.request("RGGathering") { precondition(!$0) }
        timeout.clock.advance(15)
        timeout.coordinator.request(nil, forceApply: true) { precondition($0) }
        timeout.finish(0, true)
        timeout.finish(1, true)
        precondition(Fixture(defaults).coordinator.currentIconName == nil, "A late completion cannot revive a timed-out selection")

        for name in ["RGAnime", "RGDefault", "SGNight", "BlueIcon", "PremiumTurbo", "removed-future-icon"] {
            defaults.set(["version": 1, "primary": false, "name": name, "pending": false], forKey: RGAppIconSelectionStore.key)
            let retired = Fixture(defaults, system: name)
            precondition(retired.coordinator.currentIconName == nil, "Saved retired icons must resolve to primary")
            precondition(retired.selection.needsRetiredIconReset(systemName: name))
            retired.coordinator.request(nil, forceApply: true) { precondition($0) }
            precondition(retired.requests.count == 1)
            retired.finish(0, true)
            precondition(defaults.dictionary(forKey: RGAppIconSelectionStore.key)?["primary"] as? Bool == true)
            retired.coordinator.request("RGGathering") { precondition($0) }
            precondition(!retired.selection.needsRetiredIconReset(systemName: name), "A foreground migration cannot interrupt a new request")
            retired.finish(1, true)
            precondition(!retired.selection.needsRetiredIconReset(systemName: name), "A stale retired getter cannot undo an acknowledged new icon")
            precondition(retired.selection.resolvedName(systemName: name) == "RGGathering")
        }
        for name in ["", "Components/AppBadge", "SkyAppBadge", "RegramAppBadge", "unknown"] {
            precondition(RGAppBadgeNames.canonicalName(name) == RGAppBadgeNames.defaultName)
        }
        precondition(RGAppBadgeNames.canonicalName(RGAppBadgeNames.alternateName) == RGAppBadgeNames.alternateName)
        precondition(defaults.string(forKey: "unrelated-setting") == "keep")
        print("Icon persistence passed: cold starts, stale getters, primary reset, failure/timeout/late callbacks, retired icon migration, acknowledged-selection protection and badge fallback.")
    }
}

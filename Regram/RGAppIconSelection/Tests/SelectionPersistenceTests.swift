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
        let existing = Fixture(defaults, system: "RGBlack")
        precondition(existing.coordinator.currentIconName == "RGBlack")
        precondition(Fixture(defaults).coordinator.currentIconName == "RGBlack", "An existing installation's observed alternate must be saved without requiring reselection")
        defaults.removeObject(forKey: RGAppIconSelectionStore.key)
        let first = Fixture(defaults)
        first.coordinator.request("RGBlack") { precondition($0) }
        first.finish(0, true)
        let restarted = Fixture(defaults)
        precondition(restarted.coordinator.currentIconName == "RGBlack", "A cold nil getter cannot erase the acknowledged selection")
        restarted.coordinator.resume(); restarted.clock.advance(2)
        precondition(restarted.coordinator.currentIconName == "RGBlack")
        restarted.system = "RGBlack"; restarted.coordinator.resume()
        let confirmedRestart = Fixture(defaults)
        precondition(confirmedRestart.coordinator.currentIconName == "RGBlack", "Even a previously confirmed icon must survive a cold nil getter")
        let prior = defaults.dictionary(forKey: RGAppIconSelectionStore.key)! as NSDictionary
        confirmedRestart.coordinator.request("RGGold") { precondition(!$0) }
        confirmedRestart.finish(0, false)
        precondition(prior == defaults.dictionary(forKey: RGAppIconSelectionStore.key)! as NSDictionary, "Failed changes must not replace persistence")
        confirmedRestart.coordinator.request(nil) { precondition($0) }
        confirmedRestart.finish(1, true)
        precondition(defaults.dictionary(forKey: RGAppIconSelectionStore.key)?["primary"] as? Bool == true)
        let primaryRestart = Fixture(defaults, system: "RGBlack")
        precondition(primaryRestart.coordinator.currentIconName == nil, "Persist a primary reset even while UIKit reports the old alternate")
        primaryRestart.system = nil; primaryRestart.coordinator.resume()

        let missingCallback = Fixture(defaults)
        var result: Bool?
        missingCallback.coordinator.request("RGGold") { result = $0 }
        missingCallback.system = "RGGold"; missingCallback.clock.advance(15)
        precondition(result == true && Fixture(defaults).coordinator.currentIconName == "RGGold", "Observed transitions without callbacks must persist")
        let resetWithoutCallback = Fixture(defaults, system: "RGGold")
        resetWithoutCallback.coordinator.request(nil) { precondition($0) }
        resetWithoutCallback.system = nil; resetWithoutCallback.clock.advance(15)
        precondition(Fixture(defaults, system: "RGGold").coordinator.currentIconName == nil)

        let timeout = Fixture(defaults)
        timeout.coordinator.request("RGBlack") { precondition(!$0) }
        timeout.clock.advance(15)
        timeout.coordinator.request("RGGold") { precondition($0) }
        timeout.finish(0, true) // An interrupted request's late callback must be ignored.
        timeout.finish(1, true)
        precondition(Fixture(defaults).coordinator.currentIconName == "RGGold")
        precondition(defaults.string(forKey: "unrelated-setting") == "keep")
        print("Icon persistence passed: cold starts, stale getters, observed transitions, primary reset, real failures, missing/late callbacks and unrelated preferences.")
    }
}

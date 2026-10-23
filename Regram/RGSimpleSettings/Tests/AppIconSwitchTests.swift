import Foundation

private final class Clock {
    var now: Double = 0
    var events: [(Double, () -> Void)] = []
    func schedule(_ delay: Double, _ body: @escaping () -> Void) { events.append((now + delay, body)) }
    func advance(_ delta: Double) {
        let end = now + delta
        while let index = events.indices.filter({ events[$0].0 <= end }).min(by: { events[$0].0 < events[$1].0 }) {
            let item = events.remove(at: index); now = item.0; item.1()
        }
        now = end
    }
}

private final class Fixture {
    var system: String?
    var foreground = true
    var requests: [(String?, (Bool) -> Void)] = []
    var notifications: [String?] = []
    let clock = Clock()
    lazy var coordinator: RGAppIconSwitchCoordinator = RGAppIconSwitchCoordinator(current: { [unowned self] in
        precondition(Thread.isMainThread, "UIKit must only be read on main")
        return self.system
    }, apply: { [unowned self] in self.requests.append(($0, $1)) }, changed: { [unowned self] in
        self.notifications.append(self.coordinator.currentIconName)
    }, canApply: { [unowned self] in self.foreground }, schedule: { [unowned self] in self.clock.schedule($0, $1) })
    init(_ system: String? = nil) { self.system = system }
    func request(_ name: String?, _ completed: @escaping (Bool) -> Void) { coordinator.request(name, completion: completed) }
}

@main enum IconChecks {
    static func main() {
        let unchanged = Fixture()
        for _ in 0..<20 { unchanged.coordinator.resume() }
        precondition(unchanged.requests.isEmpty && unchanged.notifications.isEmpty, "Foreground reconciliation must neither switch an icon nor redraw an unchanged selection")
        let delayed = Fixture(); var results: [Bool] = []
        delayed.request("RGBlack") { results.append($0) }
        delayed.requests[0].1(true)
        precondition(results == [true] && delayed.coordinator.currentIconName == "RGBlack")
        delayed.coordinator.resume(); delayed.clock.advance(2)
        precondition(delayed.coordinator.currentIconName == "RGBlack", "A foreground event or delayed getter must not restore Default after success")
        delayed.system = "RGBlack"; delayed.coordinator.resume()
        delayed.system = "RGGold"; delayed.coordinator.resume()
        precondition(delayed.coordinator.currentIconName == "RGGold", "After confirmation, genuine system changes must be reflected")

        let reset = Fixture("RGDefault"); var resetResult = false
        reset.request(nil) { resetResult = $0 }; precondition(reset.requests.count == 1)
        reset.requests[0].1(true); reset.coordinator.resume(); reset.clock.advance(2)
        precondition(resetResult && reset.coordinator.currentIconName == nil, "A primary reset must stay selected while the legacy getter lags")
        reset.system = nil; reset.coordinator.resume()
        reset.request("RGSilver") { precondition($0) }; reset.requests[1].1(true)
        precondition(reset.coordinator.currentIconName == "RGSilver")
        reset.request(nil) { precondition($0) }
        precondition(reset.requests.count == 3, "A stale nil getter cannot turn resetting the acknowledged alternate into a no-op")
        reset.requests[2].1(true)

        let failed = Fixture("RGGold"); var failedResults: [Bool] = []
        failed.request("RGWhite") { failedResults.append($0) }; failed.requests[0].1(false)
        precondition(failedResults == [false] && failed.coordinator.currentIconName == "RGGold")
        failed.request("RGBlack") { precondition($0) }; failed.requests[1].1(true)
        failed.request("RGWhite") { failedResults.append($0) }; failed.requests[2].1(false)
        precondition(failedResults == [false, false] && failed.coordinator.currentIconName == "RGBlack", "Failure must retain the previous acknowledged icon even when its getter is stale")

        let queued = Fixture(); queued.foreground = false
        queued.request("RGBlack") { precondition($0) }
        queued.request("RGGold") { precondition($0) }
        precondition(queued.requests.isEmpty)
        queued.foreground = true; queued.coordinator.resume()
        precondition(queued.requests.count == 1 && queued.requests[0].0 == "RGGold")
        queued.request("RGWhite") { precondition($0) }
        queued.foreground = false; queued.requests[0].1(true)
        precondition(queued.requests.count == 1, "A system confirmation may make the application inactive; do not start the next icon request then")
        queued.foreground = true; queued.coordinator.resume()
        precondition(queued.requests.count == 2 && queued.requests[1].0 == "RGWhite")
        queued.requests[1].1(true)
        queued.clock.advance(20)
        precondition(queued.coordinator.currentIconName == "RGWhite")

        let interrupted = Fixture(); var interruptedResults: [Bool] = []
        interrupted.request("RGBlack") { interruptedResults.append($0) }
        interrupted.clock.advance(15)
        precondition(interruptedResults == [false])
        interrupted.request("RGGold") { interruptedResults.append($0) }
        interrupted.requests[0].1(true)
        precondition(interrupted.coordinator.currentIconName == nil, "Late interrupted callbacks must not overwrite a newer request")
        interrupted.requests[1].1(true); interrupted.clock.advance(20)
        precondition(interruptedResults == [false, true] && interrupted.coordinator.currentIconName == "RGGold")

        let observed = Fixture(); var observedResult = false
        observed.request("RGBlack") { observedResult = $0 }; observed.system = "RGBlack"; observed.clock.advance(15)
        precondition(observedResult && observed.coordinator.currentIconName == "RGBlack", "A missing callback may be reconciled from an observed system transition")

        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async { precondition(delayed.coordinator.currentIconName == "RGGold"); group.leave() }
        precondition(group.wait(timeout: .now() + 2) == .success)
        precondition(RGAppIconNames.canonicalName("SGAnime") == nil)
        let forced = Fixture()
        forced.coordinator.request(nil, forceApply: true) { precondition($0) }
        precondition(forced.requests.count == 1, "Retired artwork must be reset even when persistence already resolves to primary")
        forced.requests[0].1(true)
        print("App icons: UIKit acknowledgement with delayed getter, quiet success, foreground gating, ordered requests, primary reset, legacy names, true failure, timeout/late callbacks and background snapshots passed.")
    }
}

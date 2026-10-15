// MARK: Regram — serialize UIKit icon requests; every completion reads the actual system state.
import Foundation

public final class RGAppIconSwitchCoordinator {
    private struct Request {
        let name: String?
        let completion: (Bool) -> Void
    }
    private let current: () -> String?
    private let apply: (String?, @escaping (Bool) -> Void) -> Void
    private let changed: () -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var queued: Request?
    private var active: UUID?

    public init(current: @escaping () -> String?, apply: @escaping (String?, @escaping (Bool) -> Void) -> Void, changed: @escaping () -> Void, schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) }) {
        self.current = current; self.apply = apply; self.changed = changed; self.schedule = schedule
    }

    public func request(_ name: String?, completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        let previous = queued
        queued = Request(name: name, completion: completion)
        // Superseded taps still finish, but must not display a failure alert.
        previous?.completion(true)
        drain()
    }

    private func matches(_ name: String?) -> Bool {
        let actual = current()
        // The primary icon has no UIKit identifier. A legacy alternate named Default can have
        // different artwork, so choosing the primary must really call setAlternateIconName(nil).
        guard let name else { return actual == nil }
        return RGAppIconNames.canonicalName(actual) == RGAppIconNames.canonicalName(name)
    }
    private func drain() {
        guard active == nil, let request = queued else { return }
        queued = nil
        if matches(request.name) { changed(); request.completion(true); drain(); return }
        let ticket = UUID()
        active = ticket
        let finish: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            precondition(Thread.isMainThread)
            self.changed()
            guard self.active == ticket else { return }
            self.active = nil
            let success = self.matches(request.name)
            request.completion(success || self.queued != nil)
            self.drain()
        }
        apply(request.name, finish)
        // An interrupted system sheet must not permanently block subsequent taps.
        schedule(15) { [weak self] in guard self?.active == ticket else { return }; finish(false) }
    }
}

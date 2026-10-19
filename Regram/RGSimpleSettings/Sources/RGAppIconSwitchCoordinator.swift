// MARK: Regram — serialize UIKit requests; its completion acknowledges the applied selection.
import Foundation

public final class RGAppIconSwitchCoordinator {
    private struct Request {
        let name: String?
        let completion: (Bool) -> Void
    }
    private struct AcceptedSelection {
        let ticket: UUID
        let name: String?
    }
    private let current: () -> String?
    private let apply: (String?, @escaping (Bool) -> Void) -> Void
    private let changed: () -> Void
    private let canApply: () -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let snapshotLock = NSLock()
    private var snapshot: String?
    private var accepted: AcceptedSelection?
    private var queued: Request?
    private var active: UUID?

    public init(current: @escaping () -> String?, apply: @escaping (String?, @escaping (Bool) -> Void) -> Void, changed: @escaping () -> Void, canApply: @escaping () -> Bool = { true }, schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) }) {
        precondition(Thread.isMainThread)
        self.current = current; self.apply = apply; self.changed = changed; self.canApply = canApply; self.schedule = schedule
        self.snapshot = current()
    }

    /// Layout may read this off-main; all UIKit reads and mutations stay on main.
    public var currentIconName: String? {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        return snapshot
    }

    public func request(_ name: String?, completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        let previous = queued
        queued = Request(name: name, completion: completion)
        previous?.completion(true)
        drain()
    }

    /// Resume after the system confirmation sheet or foreground transition.
    public func resume() {
        precondition(Thread.isMainThread)
        refreshFromSystem()
        drain()
    }

    private static func matches(_ actual: String?, _ requested: String?) -> Bool {
        // The primary icon has no identifier; a legacy alternate named Default still needs reset.
        guard let requested else { return actual == nil }
        return RGAppIconNames.canonicalName(actual) == RGAppIconNames.canonicalName(requested)
    }

    private func updateSnapshot(_ name: String?) {
        snapshotLock.lock(); snapshot = name; snapshotLock.unlock()
        changed()
    }

    private func refreshFromSystem() {
        let actual = current()
        if let accepted {
            // UIKit's getter/foreground notification can lag its successful completion. Do not
            // overwrite the acknowledged icon with that old value or call the operation failed.
            guard Self.matches(actual, accepted.name) else { return }
            self.accepted = nil
        }
        updateSnapshot(actual)
    }

    private func drain() {
        guard active == nil, let request = queued, canApply() else { return }
        refreshFromSystem()
        queued = nil
        if Self.matches(currentIconName, request.name) {
            request.completion(true)
            drain()
            return
        }
        let ticket = UUID()
        let previousSystemName = current()
        active = ticket
        apply(request.name) { [weak self] success in
            guard let self else { return }
            precondition(Thread.isMainThread)
            guard self.active == ticket else { return }
            self.complete(request, ticket: ticket, success: success)
        }
        schedule(15) { [weak self] in
            guard let self, self.active == ticket else { return }
            let actual = self.current()
            let observedChange = actual != previousSystemName && Self.matches(actual, request.name)
            self.complete(request, ticket: ticket, success: observedChange)
        }
    }

    private func complete(_ request: Request, ticket: UUID, success: Bool) {
        active = nil
        if success {
            accepted = AcceptedSelection(ticket: ticket, name: request.name)
            updateSnapshot(request.name)
            // Reconcile asynchronously, without turning an acknowledged change into an error.
            for delay in [0.2, 0.6, 1.5] {
                schedule(delay) { [weak self] in
                    guard let self, self.accepted?.ticket == ticket else { return }
                    self.refreshFromSystem()
                }
            }
        } else {
            refreshFromSystem()
        }
        request.completion(success || queued != nil)
        drain()
    }
}

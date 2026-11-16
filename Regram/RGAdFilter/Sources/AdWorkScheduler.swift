import Foundation

/// A cancellation handle is independent of UI signal delivery. Disposing a preview must also
/// stop its queued inference, not merely discard the expensive result after it is computed.
public final class RGAdWorkRequest {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

public struct RGAdWorkConditions: Equatable {
    public var foreground: Bool
    public var lowPower: Bool
    /// ProcessInfo.ThermalState raw value: nominal, fair, serious, critical.
    public var thermal: Int
    public init(foreground: Bool = true, lowPower: Bool = false, thermal: Int = 0) {
        self.foreground = foreground; self.lowPower = lowPower; self.thermal = thermal
    }
    public var paused: Bool { !foreground || thermal >= 3 }
    public func recoveryDelay(workDuration: TimeInterval) -> TimeInterval {
        let multiplier = thermal >= 2 ? 7.0 : lowPower ? 3.0 : thermal == 1 ? 2.0 : 1.0
        return max(0.005, workDuration * multiplier)
    }
}

/// One shared pump per account, with round-robin progress across chat/history/pinned scopes.
/// Calls and jobs run on `queue`. A step finishes one message atomically; between messages the
/// pump yields after 12 ms accumulated work (one message can exceed that budget). Cooldown applies to the entire pump, so multiple lists cannot
/// multiply the CPU budget. Pauses retain unfinished work without caching a "normal" verdict.
public final class RGAdWorkScheduler {
    private struct Job {
        let cancelled: () -> Bool
        let step: () -> Bool
        let onCancel: () -> Void
    }
    private let queue: DispatchQueue
    private var conditions = RGAdWorkConditions()
    private var jobs: [Job] = []
    private var scheduled: DispatchWorkItem?
    private var readyAt: TimeInterval = 0
    public init(queue: DispatchQueue) { self.queue = queue }

    public func updateConditions(_ value: RGAdWorkConditions) {
        conditions = value
        pruneCancelled()
        if value.paused { scheduled?.cancel(); scheduled = nil }
        schedule()
    }

    public func enqueue(cancelled: @escaping () -> Bool, step: @escaping () -> Bool, onCancel: @escaping () -> Void) {
        pruneCancelled()
        jobs.append(Job(cancelled: cancelled, step: step, onCancel: onCancel))
        schedule()
    }

    private func pruneCancelled() {
        let previous = jobs
        jobs.removeAll(keepingCapacity: true)
        for job in previous {
            if job.cancelled() { job.onCancel() } else { jobs.append(job) }
        }
    }

    private func schedule() {
        guard !conditions.paused, !jobs.isEmpty, scheduled == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.pump() }
        scheduled = work
        queue.asyncAfter(deadline: .now() + max(0, readyAt - ProcessInfo.processInfo.systemUptime), execute: work)
    }

    private func pump() {
        scheduled = nil
        guard !conditions.paused else { return }
        let start = ProcessInfo.processInfo.systemUptime
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            if job.cancelled() { job.onCancel() }
            else if !autoreleasepool(invoking: job.step) { jobs.append(job) }
            if ProcessInfo.processInfo.systemUptime - start >= 0.012 { break }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        readyAt = ProcessInfo.processInfo.systemUptime + conditions.recoveryDelay(workDuration: elapsed)
        schedule()
    }
}

// MARK: Regram — external ActivityKit boundary; coordinator and shared schema compile unchanged.
import Foundation
public protocol ActivityAttributes: Codable { associatedtype ContentState: Codable & Hashable }
public enum ActivityState { case active, ended, dismissed }
public enum ActivityUIDismissalPolicy { case immediate }
public struct ActivityContent<State> { public let state: State; public let staleDate: Date?; public init(state: State, staleDate: Date?) { self.state = state; self.staleDate = staleDate } }
@MainActor public enum ActivityFixture {
    public static var all: [Any] = []
    public static var enabled = true
    public static var requests = 0
    public static var endCalls = 0
    public static var suspendUpdate = false
    public static var pending: CheckedContinuation<Void, Never>?
}
@MainActor public struct ActivityAuthorizationInfo {
    public init() {}
    public var areActivitiesEnabled: Bool { ActivityFixture.enabled }
}
@MainActor public final class Activity<A: ActivityAttributes> {
    public let attributes: A
    public var state: A.ContentState
    public var activityState = ActivityState.active
    public var staleDate: Date?
    init(attributes: A, state: A.ContentState) { self.attributes = attributes; self.state = state }
    public static var activities: [Activity<A>] { ActivityFixture.all.compactMap { $0 as? Activity<A> }.filter { $0.activityState == .active } }
    public static func request(attributes: A, content: ActivityContent<A.ContentState>, pushType: Int?) throws -> Activity<A> {
        let activity = Activity(attributes: attributes, state: content.state); activity.staleDate = content.staleDate
        ActivityFixture.requests += 1; ActivityFixture.all.append(activity); return activity
    }
    public static func request(attributes: A, contentState: A.ContentState, pushType: Int?) throws -> Activity<A> { try request(attributes: attributes, content: ActivityContent(state: contentState, staleDate: nil), pushType: pushType) }
    public func update(_ content: ActivityContent<A.ContentState>) async {
        if ActivityFixture.suspendUpdate { await withCheckedContinuation { ActivityFixture.pending = $0 } }
        state = content.state; staleDate = content.staleDate
    }
    public func update(using state: A.ContentState) async { await update(ActivityContent(state: state, staleDate: nil)) }
    public func end(_ content: ActivityContent<A.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy) async { activityState = .ended; ActivityFixture.endCalls += 1 }
    public func end(dismissalPolicy: ActivityUIDismissalPolicy) async { await end(nil, dismissalPolicy: dismissalPolicy) }
}

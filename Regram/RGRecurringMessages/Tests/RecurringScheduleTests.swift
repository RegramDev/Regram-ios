import Foundation

@main struct RecurringScheduleTests {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-03-08T09:30:00Z")!
        let start = Int32(now.timeIntervalSince1970)
        let today = RGRecurringSchedulePolicy.dayKey(now, calendar: calendar)
        check(RGRecurringSchedulePolicy.shouldRun(start: start, lastSentDay: nil, now: now, calendar: calendar), "first launch")
        check(!RGRecurringSchedulePolicy.shouldRun(start: start, lastSentDay: today, now: now.addingTimeInterval(3600), calendar: calendar), "same day across DST transition")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        check(RGRecurringSchedulePolicy.shouldRun(start: start, lastSentDay: today, now: tomorrow, calendar: calendar), "next calendar day")
        check(RGRecurringSchedulePolicy.shouldRun(start: start, lastSentDay: today, now: now.addingTimeInterval(10 * 86400), calendar: calendar), "missed days produce one due task")
        check(!RGRecurringSchedulePolicy.shouldRun(start: start + 86400, lastSentDay: nil, now: now, calendar: calendar), "respect future starting date")
        check(!RGRecurringSchedulePolicy.shouldRun(start: start, lastSentDay: today + 1, now: now, calendar: calendar), "clock rollback does not repeat")
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        check(RGRecurringSchedulePolicy.dayKey(now, calendar: calendar) == 20260308, "use device calendar")
        print("Daily startup policy: 7 checks passed")
    }
}

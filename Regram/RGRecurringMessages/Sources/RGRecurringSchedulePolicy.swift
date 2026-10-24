import Foundation

// A device task is distinct from Telegram's positive server repeat periods.
public let rgStartupDailyRepeatPeriod: Int32 = -86400

enum RGRecurringSchedulePolicy {
    static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    static func shouldRun(start: Int32, lastSentDay: Int?, now: Date, calendar: Calendar) -> Bool {
        let today = dayKey(now, calendar: calendar)
        let firstDay = dayKey(Date(timeIntervalSince1970: TimeInterval(start)), calendar: calendar)
        return today >= firstDay && today > (lastSentDay ?? 0)
    }
}

import Foundation

public enum FloatingSize: String, Codable, CaseIterable { case small, medium, large }
public enum FloatingFont: String, Codable, CaseIterable { case rounded, system, monospaced }
public enum FloatingAppearance: String, Codable, CaseIterable { case system, light, dark }
public enum FloatingContent: String, Codable, CaseIterable { case amount, amountAndCountdown }

public struct FloatingPreferences: Codable, Equatable {
    public var size: FloatingSize = .medium
    public var font: FloatingFont = .rounded
    public var appearance: FloatingAppearance = .system
    public var content: FloatingContent = .amount
    public var backgroundOpacity: Double = 1
    public init() {}
    public var width: Double { size == .small ? 260 : (size == .medium ? 310 : 370) }
    public var height: Double {
        let base: Double = size == .small ? 80 : (size == .medium ? 96 : 112)
        return base + (content == .amountAndCountdown ? 28 : 0)
    }
    public var fontSize: Double { size == .small ? 22 : (size == .medium ? 28 : 34) }
}

public struct IncomeGoal: Codable, Equatable {
    public var enabled: Bool = false
    public var name: String = "今天的小目标"
    public var amount: Double = 100
    public var celebrate: Bool = true
    public init() {}
}

public struct ReminderPreferences: Codable, Equatable {
    public var offWorkEnabled: Bool = false
    public var leadMinutes: Int = 5
    public var paydayEnabled: Bool = false
    public var paydayDay: Int = 10
    public var paydayNotification: Bool = false
    public var paydayMinute: Int = 9 * 60
    public var soundEnabled: Bool = false
    public init() {}
    public var needsNotificationPermission: Bool { offWorkEnabled || (paydayEnabled && paydayNotification) }
}

public struct DesktopPreferences: Codable, Equatable {
    public var floating = FloatingPreferences()
    public var goal = IncomeGoal()
    public var reminders = ReminderPreferences()
    public init() {}
    public var validationError: String? {
        guard floating.backgroundOpacity.isFinite, (0.5...1).contains(floating.backgroundOpacity) else { return "浮窗背景透明度须在 50% 到 100% 之间。" }
        if goal.enabled {
            guard !goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, goal.name.count <= 24 else {
                return "请填写 1 到 24 个字的目标名称。"
            }
        }
        guard goal.amount.isFinite, goal.amount > 0, goal.amount <= 100_000_000 else { return "小目标金额须大于 0、不超过 1 亿。" }
        guard (0...60).contains(reminders.leadMinutes), (1...31).contains(reminders.paydayDay),
              (0..<1440).contains(reminders.paydayMinute) else { return "请检查提醒时间和发薪日期。" }
        return nil
    }
}

public struct DailyGoalProgress {
    public var fraction: Double
    public var remainingAmount: Double
    public var remainingWorkSeconds: TimeInterval?
    public var completionDate: Date?
    public var reached: Bool { remainingAmount <= 0.0000001 }
}

public struct DailyGoalCelebrationTracker {
    public var lastCelebratedDay: String?
    private var previous: (key: String, earned: Double)?
    public init(lastCelebratedDay: String? = nil) { self.lastCelebratedDay = lastCelebratedDay }
    public mutating func resetBaseline() { previous = nil }
    public mutating func shouldCelebrate(day: String, goal: IncomeGoal, earned: Double, hidden: Bool) -> Bool {
        guard goal.enabled else { previous = nil; return false }
        let key = "\(day)|\(goal.name)|\(goal.amount)"
        let before = previous
        previous = (key, earned)
        guard let before, before.key == key, before.earned < goal.amount, earned >= goal.amount,
              goal.celebrate, !hidden, lastCelebratedDay != day else { return false }
        lastCelebratedDay = day
        return true
    }
}

extension SalaryEngine {
    /// Goals reset at local midnight; their estimate skips breaks and stops at today's end.
    public func goalProgress(at now: Date, settings: SalarySettings, goal: IncomeGoal,
                             snapshot supplied: EarningsSnapshot? = nil) -> DailyGoalProgress? {
        guard goal.enabled, goal.amount.isFinite, goal.amount > 0, settings.validationError == nil else { return nil }
        let snapshot = supplied ?? self.snapshot(at: now, settings: settings)
        let remaining = max(0, goal.amount - snapshot.todayEarned)
        let fraction = min(1, max(0, snapshot.todayEarned / goal.amount))
        if remaining <= 0.0000001 { return DailyGoalProgress(fraction: 1, remainingAmount: 0, remainingWorkSeconds: 0, completionDate: now) }
        guard snapshot.secondRate > 0 else { return DailyGoalProgress(fraction: fraction, remainingAmount: remaining) }
        let needed = remaining / snapshot.secondRate
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let remainingIntervals = plannedShifts(from: now, to: tomorrow, settings: settings).flatMap(\.paid)
            .filter { $0.end > now && $0.start < tomorrow }.sorted { $0.start < $1.start }
        var secondsLeft = needed
        for interval in remainingIntervals {
            let start = max(now, interval.start)
            let end = min(tomorrow, interval.end)
            let available = max(0, end.timeIntervalSince(start))
            if secondsLeft <= available + 0.0000001 {
                return DailyGoalProgress(fraction: fraction, remainingAmount: remaining,
                                         remainingWorkSeconds: needed, completionDate: start.addingTimeInterval(secondsLeft))
            }
            secondsLeft -= available
        }
        return DailyGoalProgress(fraction: fraction, remainingAmount: remaining)
    }
}

public struct LocalReminder: Equatable {
    public enum Kind: String { case offWork, payday }
    public var id: String
    public var date: Date
    public var kind: Kind
}

public struct ReminderPlanner {
    public var calendar: Calendar
    public init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    public func nextPayday(after now: Date, day: Int, minute: Int) -> Date? {
        guard (1...31).contains(day), (0..<1440).contains(minute),
              let currentMonth = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        for offset in 0...2 {
            let month = calendar.date(byAdding: .month, value: offset, to: currentMonth)!
            let actualDay = min(day, calendar.range(of: .day, in: .month, for: month)!.count)
            let date = calendar.date(byAdding: .day, value: actualDay - 1, to: month)!
            let time = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date)!
            if time >= now { return time }
        }
        return nil
    }

    public func reminders(after now: Date, settings: SalarySettings, preferences: ReminderPreferences) -> [LocalReminder] {
        guard settings.validationError == nil else { return [] }
        var result: [LocalReminder] = []
        if preferences.offWorkEnabled {
            let end = calendar.date(byAdding: .day, value: 32, to: calendar.startOfDay(for: now))!
            for shift in SalaryEngine(calendar: calendar).plannedShifts(from: now, to: end, settings: settings) {
                let date = shift.full.end.addingTimeInterval(-Double(preferences.leadMinutes) * 60)
                if date > now, date >= shift.full.start {
                    result.append(LocalReminder(id: "paypulse.offWork.\(LocalDay.key(for: shift.workDate, calendar: calendar))", date: date, kind: .offWork))
                }
            }
        }
        if preferences.paydayEnabled && preferences.paydayNotification {
            var after = now
            for _ in 0..<3 {
                guard let date = nextPayday(after: after, day: preferences.paydayDay, minute: preferences.paydayMinute) else { break }
                result.append(LocalReminder(id: "paypulse.payday.\(LocalDay.key(for: date, calendar: calendar))", date: date, kind: .payday))
                after = date.addingTimeInterval(1)
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}

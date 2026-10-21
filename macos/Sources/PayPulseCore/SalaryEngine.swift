import Foundation

public enum PayBasis: String, Codable, CaseIterable {
    case calendar, fixed
}

public struct SalarySettings: Codable, Equatable {
    public var monthlySalary: Double = 0
    public var startMinute: Int = 9 * 60
    public var endMinute: Int = 18 * 60
    public var breakEnabled: Bool = true
    public var breakStartMinute: Int = 12 * 60
    public var breakEndMinute: Int = 13 * 60
    /// Foundation weekday: Sunday = 1, Monday = 2.
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public var basis: PayBasis = .calendar
    public var fixedDays: Double = 21.75
    public var hideAmounts: Bool = false
    public var showFourDecimals: Bool = false

    public init() {}

    public var shiftMinutes: Int {
        (endMinute - startMinute + 1440) % 1440
    }
    public var breakOffsets: (start: Int, end: Int) {
        let start = (breakStartMinute - startMinute + 1440) % 1440
        let duration = (breakEndMinute - breakStartMinute + 1440) % 1440
        return (start, start + duration)
    }
    public var paidMinutes: Int {
        shiftMinutes - (breakEnabled ? breakOffsets.end - breakOffsets.start : 0)
    }
    public var validationError: String? {
        guard monthlySalary.isFinite, monthlySalary > 0, monthlySalary <= 100_000_000 else {
            return "请输入大于 0、不超过 1 亿的月薪。"
        }
        guard [startMinute, endMinute, breakStartMinute, breakEndMinute].allSatisfy({ (0..<1440).contains($0) }) else {
            return "时间必须在 00:00 到 23:59 之间。"
        }
        guard shiftMinutes > 0 else { return "上班和下班时间不能相同。" }
        guard !weekdays.isEmpty, weekdays.allSatisfy({ (1...7).contains($0) }) else {
            return "请至少选择一个工作日。"
        }
        if breakEnabled {
            let b = breakOffsets
            guard b.end > b.start, b.start > 0, b.end < shiftMinutes else {
                return "休息时段须完整位于上下班之间，且开始、结束时间不同。"
            }
        }
        if basis == .fixed {
            guard fixedDays.isFinite, fixedDays > 0, fixedDays <= 31 else { return "固定计薪天数须大于 0 且不超过 31。" }
        }
        return nil
    }
    public static func timeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

public enum WorkState: String {
    case working, onBreak, waiting, finished, dayOff, unconfigured
    public var title: String {
        switch self {
        case .working: return "正在计薪"
        case .onBreak: return "休息时间"
        case .waiting: return "等待上班"
        case .finished: return "已下班"
        case .dayOff: return "今日休息"
        case .unconfigured: return "尚未设置"
        }
    }
}

public struct EarningsSnapshot {
    public var todayEarned: Double = 0
    public var monthEarned: Double = 0
    public var dailyTarget: Double = 0
    public var hourlyRate: Double = 0
    public var earnedSeconds: TimeInterval = 0
    public var plannedSeconds: TimeInterval = 0
    public var monthScheduledSeconds: TimeInterval = 0
    public var monthWorkdays: Int = 0
    public var state: WorkState = .unconfigured
    public var nextEvent: Date?
    public var nextEventLabel: String = ""
    public var progress: Double { plannedSeconds > 0 ? min(1, max(0, earnedSeconds / plannedSeconds)) : 0 }
    public var secondRate: Double { hourlyRate / 3600 }
    public init() {}
}

/// Rebuilds earnings from calendar intervals, never by adding timer ticks.
/// Sleep, relaunch and missed refreshes therefore do not lose scheduled earnings.
public struct SalaryEngine {
    public var calendar: Calendar
    public init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    private struct Shift {
        var full: DateInterval
        var paid: [DateInterval]
    }

    private func time(_ minuteOffset: Int, on day: Date) -> Date {
        let offset = minuteOffset / 1440
        let minute = minuteOffset % 1440
        let date = calendar.date(byAdding: .day, value: offset, to: day)!
        // Calendar wall-clock construction also handles local DST transitions.
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                             of: date, matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
    }

    private func shift(on day: Date, settings s: SalarySettings) -> Shift? {
        guard s.weekdays.contains(calendar.component(.weekday, from: day)) else { return nil }
        let start = time(s.startMinute, on: day)
        let end = time(s.startMinute + s.shiftMinutes, on: day)
        guard end > start else { return nil }
        if s.breakEnabled {
            let b = s.breakOffsets
            let bStart = time(s.startMinute + b.start, on: day)
            let bEnd = time(s.startMinute + b.end, on: day)
            let intervals = [(start, min(bStart, end)), (max(bEnd, start), end)]
                .filter { $0.1 > $0.0 }.map { DateInterval(start: $0.0, end: $0.1) }
            return Shift(full: DateInterval(start: start, end: end), paid: intervals)
        }
        return Shift(full: DateInterval(start: start, end: end), paid: [DateInterval(start: start, end: end)])
    }

    private func overlap(_ interval: DateInterval, from start: Date, to end: Date) -> TimeInterval {
        max(0, min(interval.end, end).timeIntervalSince(max(interval.start, start)))
    }

    private func shifts(from start: Date, to end: Date, settings: SalarySettings) -> [Shift] {
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start))!
        var result: [Shift] = []
        while day < end {
            if let shift = shift(on: day, settings: settings) { result.append(shift) }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    public func snapshot(at now: Date, settings s: SalarySettings) -> EarningsSnapshot {
        guard s.validationError == nil else { return EarningsSnapshot() }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let month = calendar.dateInterval(of: .month, for: now)!
        let monthlyShifts = shifts(from: month.start, to: month.end, settings: s)
        let monthlyPaid = monthlyShifts.flatMap(\.paid)
        let monthSeconds = monthlyPaid.reduce(0) { $0 + overlap($1, from: month.start, to: month.end) }
        let denominator = s.basis == .calendar ? monthSeconds : s.fixedDays * Double(s.paidMinutes) * 60
        let rate = denominator > 0 ? s.monthlySalary / denominator : 0
        let dailyShifts = shifts(from: today, to: tomorrow, settings: s)
        let dailyPaid = dailyShifts.flatMap(\.paid)
        var result = EarningsSnapshot()
        result.hourlyRate = rate * 3600
        result.plannedSeconds = dailyPaid.reduce(0) { $0 + overlap($1, from: today, to: tomorrow) }
        result.earnedSeconds = dailyPaid.reduce(0) { $0 + overlap($1, from: today, to: now) }
        result.todayEarned = result.earnedSeconds * rate
        result.dailyTarget = result.plannedSeconds * rate
        result.monthEarned = monthlyPaid.reduce(0) { $0 + overlap($1, from: month.start, to: now) } * rate
        result.monthScheduledSeconds = monthSeconds
        var day = month.start
        while day < month.end {
            if s.weekdays.contains(calendar.component(.weekday, from: day)) { result.monthWorkdays += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        if let active = dailyShifts.first(where: { now >= $0.full.start && now < $0.full.end }) {
            if active.paid.contains(where: { now >= $0.start && now < $0.end }) {
                result.state = .working
                result.nextEvent = active.full.end
                result.nextEventLabel = "距离下班"
            } else {
                result.state = .onBreak
                result.nextEvent = active.paid.first(where: { $0.start > now })?.start
                result.nextEventLabel = "休息结束"
            }
        } else if let next = dailyShifts.first(where: { $0.full.start > now && $0.full.start < tomorrow }) {
            result.state = .waiting
            result.nextEvent = next.full.start
            result.nextEventLabel = "距离上班"
        } else {
            result.state = result.plannedSeconds > 0 ? .finished : .dayOff
        }
        return result
    }
}

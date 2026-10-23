import Foundation

public enum PayBasis: String, Codable, CaseIterable {
    case calendar, fixed, china
}

public struct WorkHours: Codable, Equatable {
    public var startMinute: Int = 9 * 60
    public var endMinute: Int = 18 * 60
    public var breakEnabled: Bool = true
    public var breakStartMinute: Int = 12 * 60
    public var breakEndMinute: Int = 13 * 60
    public init() {}
    public var shiftMinutes: Int { (endMinute - startMinute + 1440) % 1440 }
    public var breakOffsets: (start: Int, end: Int) {
        let start = (breakStartMinute - startMinute + 1440) % 1440
        return (start, start + (breakEndMinute - breakStartMinute + 1440) % 1440)
    }
    public var paidMinutes: Int { shiftMinutes - (breakEnabled ? breakOffsets.end - breakOffsets.start : 0) }
    public var validationError: String? {
        guard [startMinute, endMinute, breakStartMinute, breakEndMinute].allSatisfy({ (0..<1440).contains($0) }) else {
            return "时间必须在 00:00 到 23:59 之间。"
        }
        guard shiftMinutes > 0 else { return "上班和下班时间不能相同。" }
        if breakEnabled {
            let b = breakOffsets
            guard b.end > b.start, b.start > 0, b.end < shiftMinutes else {
                return "休息时段须完整位于上下班之间，且开始、结束时间不同。"
            }
        }
        return nil
    }
    public var label: String {
        "\(SalarySettings.timeString(startMinute)) — \(SalarySettings.timeString(endMinute))\(endMinute < startMinute ? " 次日" : "")"
    }
}

public struct DayOverride: Codable, Equatable {
    public var isWorkingDay: Bool
    public var hours: WorkHours
    public init(isWorkingDay: Bool, hours: WorkHours = WorkHours()) {
        self.isWorkingDay = isWorkingDay
        self.hours = hours
    }
}

/// Stable Gregorian local-date keys, independent of display locale and time zone offsets.
public enum LocalDay {
    public static func key(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(for key: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let pieces = key.split(separator: "-")
        guard pieces.count == 3, key.count == 10,
              let year = Int(pieces[0]), (1...9999).contains(year),
              let month = Int(pieces[1]), let day = Int(pieces[2]) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard let value = gregorian.date(from: DateComponents(year: year, month: month, day: day)),
              Self.key(for: value, calendar: gregorian) == key else { return nil }
        return value
    }
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
    /// A date replaces that shift's recurring weekday rule. Overnight shifts belong to their start date.
    public var dayOverrides: [String: DayOverride] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case monthlySalary, startMinute, endMinute, breakEnabled, breakStartMinute, breakEndMinute
        case weekdays, basis, fixedDays, hideAmounts, showFourDecimals, dayOverrides
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthlySalary = try c.decodeIfPresent(Double.self, forKey: .monthlySalary) ?? 0
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 540
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute) ?? 1080
        breakEnabled = try c.decodeIfPresent(Bool.self, forKey: .breakEnabled) ?? true
        breakStartMinute = try c.decodeIfPresent(Int.self, forKey: .breakStartMinute) ?? 720
        breakEndMinute = try c.decodeIfPresent(Int.self, forKey: .breakEndMinute) ?? 780
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? [2, 3, 4, 5, 6]
        basis = try c.decodeIfPresent(PayBasis.self, forKey: .basis) ?? .calendar
        fixedDays = try c.decodeIfPresent(Double.self, forKey: .fixedDays) ?? 21.75
        hideAmounts = try c.decodeIfPresent(Bool.self, forKey: .hideAmounts) ?? false
        showFourDecimals = try c.decodeIfPresent(Bool.self, forKey: .showFourDecimals) ?? false
        dayOverrides = try c.decodeIfPresent([String: DayOverride].self, forKey: .dayOverrides) ?? [:]
    }

    public var hours: WorkHours {
        get {
            var h = WorkHours()
            h.startMinute = startMinute; h.endMinute = endMinute
            h.breakEnabled = breakEnabled; h.breakStartMinute = breakStartMinute; h.breakEndMinute = breakEndMinute
            return h
        }
        set {
            startMinute = newValue.startMinute; endMinute = newValue.endMinute
            breakEnabled = newValue.breakEnabled; breakStartMinute = newValue.breakStartMinute; breakEndMinute = newValue.breakEndMinute
        }
    }

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
        if let error = hours.validationError { return error }
        guard (basis == .china || !weekdays.isEmpty), weekdays.allSatisfy({ (1...7).contains($0) }) else {
            return "请至少选择一个工作日。"
        }
        if basis == .fixed {
            guard fixedDays.isFinite, fixedDays > 0, fixedDays <= 31 else { return "固定计薪天数须大于 0 且不超过 31。" }
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var adjacentDays: Set<String> = []
        for (key, exception) in dayOverrides {
            guard let day = LocalDay.date(for: key, calendar: utc) else { return "临时排班含有无效日期。" }
            if exception.isWorkingDay, let error = exception.hours.validationError { return "\(key)：\(error)" }
            adjacentDays.insert(key)
            adjacentDays.insert(LocalDay.key(for: utc.date(byAdding: .day, value: -1, to: day)!, calendar: utc))
        }
        // Reject overlapping adjacent shifts rather than double-counting their shared hours.
        for key in adjacentDays.sorted() {
            guard let day = LocalDay.date(for: key, calendar: utc) else { continue }
            let next = utc.date(byAdding: .day, value: 1, to: day)!
            if let a = payHours(on: day, calendar: utc), let b = payHours(on: next, calendar: utc),
               a.startMinute + a.shiftMinutes > 1440 + b.startMinute {
                return "\(key) 的跨夜排班与次日重叠，请调整上下班时间。"
            }
        }
        return nil
    }
    public func workHours(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> WorkHours? {
        if let override = dayOverrides[LocalDay.key(for: day, calendar: calendar)] {
            return override.isWorkingDay ? override.hours : nil
        }
        if basis == .china {
            guard ChinaCalendar.contains(day, calendar: calendar) else { return nil }
            if let special = ChinaCalendar.day(day, calendar: calendar) { return special.kind == "work" ? hours : nil }
            return (2...6).contains(calendar.component(.weekday, from: day)) ? hours : nil
        }
        return weekdays.contains(calendar.component(.weekday, from: day)) ? hours : nil
    }
    public func isPaidHoliday(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        basis == .china && dayOverrides[LocalDay.key(for: day, calendar: calendar)] == nil
            && ChinaCalendar.day(day, calendar: calendar)?.kind == "statutory"
    }
    public func payHours(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> WorkHours? {
        isPaidHoliday(on: day, calendar: calendar) ? hours : workHours(on: day, calendar: calendar)
    }
    public static func timeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

public enum WorkState: String {
    case working, paidHoliday, calendarUnavailable, onBreak, waiting, finished, dayOff, unconfigured
    public var title: String {
        switch self {
        case .working: return "正在计薪"
        case .paidHoliday: return "带薪休假"
        case .calendarUnavailable: return "日历待更新"
        case .onBreak: return "休息时间"
        case .waiting: return "等待计时"
        case .finished: return "今日计薪结束"
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
    public var monthPaidSeconds: TimeInterval = 0
    public var rateDenominatorSeconds: TimeInterval = 0
    public var monthWorkdays: Int = 0
    public var monthPaidHolidays: Int = 0
    public var monthPayDays: Int { monthWorkdays + monthPaidHolidays }
    public var state: WorkState = .unconfigured
    public var nextEvent: Date?
    public var nextEventLabel: String = ""
    public var progress: Double { plannedSeconds > 0 ? min(1, max(0, earnedSeconds / plannedSeconds)) : 0 }
    public var secondRate: Double { hourlyRate / 3600 }
    public init() {}
}

public struct ScheduledShift {
    public var workDate: Date
    public var full: DateInterval
    public var paid: [DateInterval]
    public var paidHoliday: Bool
}

/// Rebuilds earnings from calendar intervals, never by adding timer ticks.
/// Sleep, relaunch and missed refreshes therefore do not lose scheduled earnings.
public struct SalaryEngine {
    public var calendar: Calendar
    public init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    private func time(_ minuteOffset: Int, on day: Date) -> Date {
        let offset = minuteOffset / 1440
        let minute = minuteOffset % 1440
        let date = calendar.date(byAdding: .day, value: offset, to: day)!
        // Calendar wall-clock construction also handles local DST transitions.
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                             of: date, matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
    }

    private func shift(on day: Date, settings s: SalarySettings) -> ScheduledShift? {
        guard let hours = s.payHours(on: day, calendar: calendar) else { return nil }
        let paidHoliday = s.isPaidHoliday(on: day, calendar: calendar)
        let start = time(hours.startMinute, on: day)
        let end = time(hours.startMinute + hours.shiftMinutes, on: day)
        guard end > start else { return nil }
        if hours.breakEnabled {
            let b = hours.breakOffsets
            let bStart = time(hours.startMinute + b.start, on: day)
            let bEnd = time(hours.startMinute + b.end, on: day)
            let intervals = [(start, min(bStart, end)), (max(bEnd, start), end)]
                .filter { $0.1 > $0.0 }.map { DateInterval(start: $0.0, end: $0.1) }
            return ScheduledShift(workDate: day, full: DateInterval(start: start, end: end), paid: intervals, paidHoliday: paidHoliday)
        }
        return ScheduledShift(workDate: day, full: DateInterval(start: start, end: end), paid: [DateInterval(start: start, end: end)], paidHoliday: paidHoliday)
    }

    private func overlap(_ interval: DateInterval, from start: Date, to end: Date) -> TimeInterval {
        max(0, min(interval.end, end).timeIntervalSince(max(interval.start, start)))
    }

    private func shifts(from start: Date, to end: Date, settings: SalarySettings) -> [ScheduledShift] {
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start))!
        var result: [ScheduledShift] = []
        while day < end {
            if let shift = shift(on: day, settings: settings) { result.append(shift) }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    public func plannedShifts(from start: Date, to end: Date, settings: SalarySettings) -> [ScheduledShift] {
        guard settings.validationError == nil, end > start else { return [] }
        return shifts(from: start, to: end, settings: settings).filter { $0.full.end > start && $0.full.start < end }
    }

    public func dailyScheduleLabel(at now: Date, settings: SalarySettings) -> String {
        if settings.basis == .china, !ChinaCalendar.contains(now, calendar: calendar) {
            return ChinaCalendar.status(at: now, calendar: calendar)
        }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let relevant = plannedShifts(from: today, to: tomorrow, settings: settings)
        guard !relevant.isEmpty else { return "今日休息" }
        return relevant.map { shift in
            let start = calendar.dateComponents([.hour, .minute], from: shift.full.start)
            let end = calendar.dateComponents([.hour, .minute], from: shift.full.end)
            let holiday = shift.paidHoliday ? "\(ChinaCalendar.day(shift.workDate, calendar: calendar)?.name ?? "法定节日") · 带薪休假 " : ""
            let prefix = holiday + (shift.full.start < today ? "昨 " : "")
            let suffix = shift.full.end >= tomorrow ? " 次日" : ""
            return "\(prefix)\(SalarySettings.timeString(start.hour! * 60 + start.minute!)) — \(SalarySettings.timeString(end.hour! * 60 + end.minute!))\(suffix)"
        }.joined(separator: " · ")
    }

    public func snapshot(at now: Date, settings s: SalarySettings) -> EarningsSnapshot {
        guard s.validationError == nil else { return EarningsSnapshot() }
        if s.basis == .china, !ChinaCalendar.contains(now, calendar: calendar) {
            var unavailable = EarningsSnapshot(); unavailable.state = .calendarUnavailable; return unavailable
        }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let month = calendar.dateInterval(of: .month, for: now)!
        let monthlyShifts = shifts(from: month.start, to: month.end, settings: s)
        let monthlyPaid = monthlyShifts.flatMap(\.paid)
        let monthSeconds = monthlyPaid.reduce(0) { $0 + overlap($1, from: month.start, to: month.end) }
        let denominator = s.basis == .fixed ? s.fixedDays * Double(s.paidMinutes) * 60 : monthSeconds
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
        result.monthScheduledSeconds = monthlyShifts.filter { !$0.paidHoliday }.flatMap(\.paid)
            .reduce(0) { $0 + overlap($1, from: month.start, to: month.end) }
        result.monthPaidSeconds = monthSeconds
        result.rateDenominatorSeconds = denominator
        var day = month.start
        while day < month.end {
            if s.workHours(on: day, calendar: calendar) != nil { result.monthWorkdays += 1 }
            if s.isPaidHoliday(on: day, calendar: calendar) { result.monthPaidHolidays += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        if let active = dailyShifts.first(where: { now >= $0.full.start && now < $0.full.end }) {
            if active.paid.contains(where: { now >= $0.start && now < $0.end }) {
                result.state = active.paidHoliday ? .paidHoliday : .working
                result.nextEvent = active.full.end
                result.nextEventLabel = active.paidHoliday ? "本段计薪结束" : "距离下班"
            } else {
                result.state = .onBreak
                result.nextEvent = active.paid.first(where: { $0.start > now })?.start
                result.nextEventLabel = "休息结束"
            }
        } else if let next = dailyShifts.first(where: { $0.full.start > now && $0.full.start < tomorrow }) {
            result.state = .waiting
            result.nextEvent = next.full.start
            result.nextEventLabel = next.paidHoliday ? "带薪计时开始" : "距离上班"
        } else {
            result.state = result.plannedSeconds > 0 ? .finished : .dayOff
        }
        return result
    }
}

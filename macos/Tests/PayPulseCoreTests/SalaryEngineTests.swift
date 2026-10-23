import Foundation
import PayPulseCore

// Standalone checks run with Command Line Tools; full Xcode/XCTest is not required.
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}
func checkEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    guard abs(actual - expected) <= accuracy else { fatalError("Expected \(expected) ± \(accuracy), got \(actual)", file: file, line: line) }
}
func checkNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    guard value == nil else { fatalError("Expected nil", file: file, line: line) }
}
func checkNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    guard value != nil else { fatalError("Expected a value", file: file, line: line) }
}

final class SalaryEngineTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    func date(_ text: String, calendar: Calendar? = nil) -> Date {
        let f = DateFormatter()
        f.calendar = calendar ?? self.calendar
        f.timeZone = (calendar ?? self.calendar).timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: text)!
    }
    func settings() -> SalarySettings {
        var s = SalarySettings()
        s.monthlySalary = 18_400
        return s
    }
    func snapshot(_ time: String, _ s: SalarySettings? = nil) -> EarningsSnapshot {
        SalaryEngine(calendar: calendar).snapshot(at: date(time), settings: s ?? settings())
    }
    func testWorkdayAndLunchBoundaries() {
        let before = snapshot("2026-10-21 08:59:59")
        checkEqual(before.todayEarned, 0)
        checkEqual(before.state, .waiting)
        checkEqual(snapshot("2026-10-21 09:00:00").state, .working)
        let lunch = snapshot("2026-10-21 12:00:00")
        checkEqual(lunch.state, .onBreak)
        checkEqual(lunch.earnedSeconds, 3 * 3600)
        checkEqual(lunch.todayEarned, snapshot("2026-10-21 12:59:59").todayEarned)
        checkEqual(snapshot("2026-10-21 13:00:00").state, .working)
        let end = snapshot("2026-10-21 18:00:00")
        checkEqual(end.state, .finished)
        checkEqual(end.earnedSeconds, 8 * 3600)
        checkEqual(end.progress, 1)
        checkEqual(end.todayEarned, end.dailyTarget, accuracy: 0.00001)
        checkEqual(end.todayEarned, snapshot("2026-10-21 23:59:59").todayEarned)
    }
    func testWeekendAndDayReset() {
        checkEqual(snapshot("2026-10-24 15:00:00").state, .dayOff)
        checkEqual(snapshot("2026-10-24 15:00:00").todayEarned, 0)
        checkEqual(snapshot("2026-10-22 00:00:00").todayEarned, 0)
    }
    func testMonthlyConservationAndMonthReset() {
        let end = snapshot("2026-10-31 23:59:59")
        checkEqual(end.monthEarned, settings().monthlySalary, accuracy: 0.00001)
        checkEqual(end.monthWorkdays, 22)
        checkEqual(snapshot("2026-11-01 00:00:00").monthEarned, 0)
    }
    func testFixedBasisAndExactElapsedSeconds() {
        var s = settings()
        s.basis = .fixed
        s.fixedDays = 20
        s.monthlySalary = 16_000
        let a = snapshot("2026-10-21 09:00:00", s)
        let b = snapshot("2026-10-21 09:00:36", s)
        checkEqual(a.hourlyRate, 100, accuracy: 0.00001)
        checkEqual(b.todayEarned, 1, accuracy: 0.00001)
        // A fresh engine hours later includes the full elapsed schedule without running any timer.
        checkEqual(snapshot("2026-10-21 16:00:00", s).todayEarned, 600, accuracy: 0.00001)
    }
    func testNoUnpaidBreakAndCustomWeekdays() {
        var s = settings()
        s.breakEnabled = false
        s.weekdays = [7]
        checkEqual(snapshot("2026-10-24 12:30:00", s).state, .working)
        checkEqual(snapshot("2026-10-24 18:00:00", s).earnedSeconds, 9 * 3600)
        checkEqual(snapshot("2026-10-21 12:30:00", s).state, .dayOff)
    }
    func testOvernightShiftAndCalendarDayAllocation() {
        var s = settings()
        s.startMinute = 22 * 60
        s.endMinute = 6 * 60
        s.breakStartMinute = 2 * 60
        s.breakEndMinute = 3 * 60
        checkNil(s.validationError)
        checkEqual(snapshot("2026-10-24 01:00:00", s).state, .working) // Friday shift continues Saturday.
        checkEqual(snapshot("2026-10-24 02:30:00", s).state, .onBreak)
        checkEqual(snapshot("2026-10-24 06:00:00", s).earnedSeconds, 5 * 3600)
        checkEqual(snapshot("2026-10-24 22:00:00", s).state, .finished)
        checkEqual(snapshot("2026-10-25 01:00:00", s).state, .dayOff)
        let end = snapshot("2026-10-31 23:59:59", s)
        checkEqual(end.monthEarned, s.monthlySalary, accuracy: 0.00001)
        let start = snapshot("2026-10-01 01:00:00", s)
        checkEqual(start.state, .working)
        checkEqual(start.earnedSeconds, 3600)
    }
    func testInvalidInputsNeverProduceEarnings() {
        var s = settings()
        s.monthlySalary = .nan
        checkNotNil(s.validationError)
        checkEqual(snapshot("2026-10-21 15:00:00", s).state, .unconfigured)
        s = settings(); s.weekdays = []
        checkNotNil(s.validationError)
        s = settings(); s.startMinute = s.endMinute
        checkNotNil(s.validationError)
        s = settings(); s.breakStartMinute = 8 * 60
        checkNotNil(s.validationError)
        s = settings(); s.breakEndMinute = s.breakStartMinute
        checkNotNil(s.validationError)
        s = settings(); s.basis = .fixed; s.fixedDays = 0
        checkNotNil(s.validationError)
        s.basis = .calendar
        checkNil(s.validationError) // A hidden inactive field cannot block saving the calendar basis.
    }
    func testSettingsRoundTrip() throws {
        var s = settings()
        s.showFourDecimals = true
        s.hideAmounts = true
        s.basis = .fixed
        checkEqual(try JSONDecoder().decode(SalarySettings.self, from: JSONEncoder().encode(s)), s)
    }
    func testDSTUsesRealElapsedTimeAndMonthlyConservation() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        var s = settings()
        s.startMinute = 0; s.endMinute = 8 * 60
        s.breakEnabled = false; s.weekdays = Set(1...7)
        let engine = SalaryEngine(calendar: c)
        let spring = engine.snapshot(at: date("2026-03-08 08:00:00", calendar: c), settings: s)
        checkEqual(spring.earnedSeconds, 7 * 3600)
        let fall = engine.snapshot(at: date("2026-11-01 08:00:00", calendar: c), settings: s)
        checkEqual(fall.earnedSeconds, 9 * 3600)
        let monthEnd = engine.snapshot(at: date("2026-03-31 23:59:59", calendar: c), settings: s)
        checkEqual(monthEnd.monthEarned, s.monthlySalary, accuracy: 0.00001)
    }

    func testDayOverridesAndBothPayBases() {
        var s = settings()
        s.dayOverrides["2026-10-21"] = DayOverride(isWorkingDay: false)
        checkEqual(snapshot("2026-10-21 15:00:00", s).state, .dayOff)
        checkEqual(snapshot("2026-10-21 15:00:00", s).monthWorkdays, 21)
        var short = s.hours
        short.startMinute = 10 * 60; short.endMinute = 14 * 60; short.breakEnabled = false
        s.dayOverrides["2026-10-24"] = DayOverride(isWorkingDay: true, hours: short)
        let worked = snapshot("2026-10-24 14:00:00", s)
        checkEqual(worked.monthWorkdays, 22)
        checkEqual(worked.monthScheduledSeconds, (21 * 8 + 4) * 3600)
        checkEqual(worked.earnedSeconds, 4 * 3600)
        checkEqual(snapshot("2026-10-31 23:59:59", s).monthEarned, s.monthlySalary, accuracy: 0.00001)
        s.basis = .fixed; s.fixedDays = 20; s.monthlySalary = 16_000
        checkEqual(snapshot("2026-10-24 14:00:00", s).hourlyRate, 100, accuracy: 0.00001)
        checkEqual(snapshot("2026-10-24 14:00:00", s).todayEarned, 400, accuracy: 0.00001)
        s.fixedDays = 21.75
        checkEqual(snapshot("2026-10-24 14:00:00", s).monthWorkdays, 22)
        // Removing an exception restores the recurring schedule.
        s.dayOverrides.removeValue(forKey: "2026-10-24")
        checkEqual(snapshot("2026-10-24 14:00:00", s).state, .dayOff)
    }

    func testOvernightExceptionsAndConflictRejection() {
        var s = settings()
        var night = s.hours
        night.startMinute = 22 * 60; night.endMinute = 6 * 60; night.breakEnabled = false
        s.dayOverrides["2026-10-23"] = DayOverride(isWorkingDay: true, hours: night)
        s.dayOverrides["2026-10-24"] = DayOverride(isWorkingDay: false)
        checkNil(s.validationError)
        checkEqual(snapshot("2026-10-24 01:00:00", s).state, .working)
        checkEqual(snapshot("2026-10-24 06:00:00", s).earnedSeconds, 6 * 3600)
        var early = s.hours; early.startMinute = 5 * 60; early.endMinute = 12 * 60; early.breakEnabled = false
        s.dayOverrides["2026-10-24"] = DayOverride(isWorkingDay: true, hours: early)
        checkNotNil(s.validationError)
        early.startMinute = 6 * 60
        s.dayOverrides["2026-10-24"] = DayOverride(isWorkingDay: true, hours: early)
        checkNil(s.validationError)
        s.dayOverrides["2026-02-30"] = DayOverride(isWorkingDay: false)
        checkNotNil(s.validationError)
    }

    func testLegacyMigrationAndDesktopPersistence() throws {
        let legacy = """
        {"monthlySalary":18000,"startMinute":540,"endMinute":1080,"breakEnabled":true,"breakStartMinute":720,"breakEndMinute":780,"weekdays":[2,3,4,5,6],"basis":"fixed","fixedDays":21.75,"hideAmounts":true,"showFourDecimals":true}
        """
        let migrated = try JSONDecoder().decode(SalarySettings.self, from: Data(legacy.utf8))
        checkEqual(migrated.monthlySalary, 18000)
        checkEqual(migrated.hideAmounts, true)
        checkEqual(migrated.dayOverrides, [:])
        var s = migrated
        s.dayOverrides["2026-10-24"] = DayOverride(isWorkingDay: true, hours: s.hours)
        checkEqual(try JSONDecoder().decode(SalarySettings.self, from: JSONEncoder().encode(s)), s)
        var prefs = DesktopPreferences()
        prefs.floating.appearance = .dark; prefs.floating.backgroundOpacity = 0.7
        prefs.floating.size = .large; prefs.floating.content = .amountAndCountdown
        prefs.goal.enabled = true; prefs.goal.name = "咖啡"; prefs.goal.amount = 20
        prefs.reminders.paydayEnabled = true; prefs.reminders.paydayDay = 31
        checkEqual(try JSONDecoder().decode(DesktopPreferences.self, from: JSONEncoder().encode(prefs)), prefs)
        prefs.goal.amount = .infinity
        checkNotNil(prefs.validationError)
    }

    func testGoalEstimateSkipsBreakAndStopsAtMidnight() {
        var s = settings(); s.basis = .fixed; s.fixedDays = 20; s.monthlySalary = 16_000
        var goal = IncomeGoal(); goal.enabled = true; goal.amount = 350
        let engine = SalaryEngine(calendar: calendar)
        let progress = engine.goalProgress(at: date("2026-10-21 11:30:00"), settings: s, goal: goal)!
        checkEqual(progress.remainingWorkSeconds!, 3600, accuracy: 0.00001)
        checkEqual(progress.completionDate, date("2026-10-21 13:30:00"))
        checkEqual(engine.goalProgress(at: date("2026-10-21 13:30:00"), settings: s, goal: goal)!.reached, true)
        goal.amount = 900
        checkNil(engine.goalProgress(at: date("2026-10-21 15:00:00"), settings: s, goal: goal)!.completionDate)
        checkNil(engine.goalProgress(at: date("2026-10-24 15:00:00"), settings: s, goal: goal)!.completionDate)
        goal.amount = 50
        let next = engine.goalProgress(at: date("2026-10-22 00:00:00"), settings: s, goal: goal)!
        checkEqual(next.fraction, 0)
        checkEqual(next.completionDate, date("2026-10-22 09:30:00"))
    }

    func testPaydayShortMonthAndReminderDates() {
        let planner = ReminderPlanner(calendar: calendar)
        checkEqual(planner.nextPayday(after: date("2026-02-01 00:00:00"), day: 31, minute: 540), date("2026-02-28 09:00:00"))
        checkEqual(planner.nextPayday(after: date("2028-02-01 00:00:00"), day: 31, minute: 540), date("2028-02-29 09:00:00"))
        checkEqual(planner.nextPayday(after: date("2026-12-31 10:00:00"), day: 31, minute: 540), date("2027-01-31 09:00:00"))
        var prefs = ReminderPreferences()
        checkEqual(planner.reminders(after: date("2026-10-21 10:00:00"), settings: settings(), preferences: prefs), [])
        prefs.offWorkEnabled = true; prefs.paydayEnabled = true; prefs.paydayNotification = true; prefs.paydayDay = 25
        var s = settings(); s.dayOverrides["2026-10-22"] = DayOverride(isWorkingDay: false)
        let reminders = planner.reminders(after: date("2026-10-21 10:00:00"), settings: s, preferences: prefs)
        checkEqual(reminders.first!.date, date("2026-10-21 17:55:00"))
        checkEqual(reminders.contains { $0.id == "paypulse.offWork.2026-10-22" }, false)
        checkEqual(reminders.contains { $0.kind == .payday && $0.date == date("2026-10-25 09:00:00") }, true)
        checkEqual(Set(reminders.map(\.id)).count, reminders.count)
        checkEqual(reminders.allSatisfy { $0.date > date("2026-10-21 10:00:00") }, true)
        checkEqual(reminders.count < 40, true)
        var night = s.hours; night.startMinute = 22 * 60; night.endMinute = 6 * 60; night.breakEnabled = false
        s.dayOverrides["2026-10-23"] = DayOverride(isWorkingDay: true, hours: night)
        s.dayOverrides["2026-10-24"] = DayOverride(isWorkingDay: false)
        let overnight = planner.reminders(after: date("2026-10-24 01:00:00"), settings: s, preferences: prefs)
        checkEqual(overnight.first!.date, date("2026-10-24 05:55:00"))
        checkEqual(overnight.first!.id, "paypulse.offWork.2026-10-23")
    }

    func testGoalCelebratesOnlyOnCrossingAndRespectsPrivacy() {
        var tracker = DailyGoalCelebrationTracker()
        var goal = IncomeGoal(); goal.enabled = true; goal.amount = 100
        checkEqual(tracker.shouldCelebrate(day: "2026-10-21", goal: goal, earned: 99, hidden: false), false)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-21", goal: goal, earned: 100, hidden: false), true)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-21", goal: goal, earned: 101, hidden: false), false)
        tracker.resetBaseline()
        checkEqual(tracker.shouldCelebrate(day: "2026-10-21", goal: goal, earned: 99, hidden: false), false)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-21", goal: goal, earned: 100, hidden: false), false)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-22", goal: goal, earned: 99, hidden: true), false)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-22", goal: goal, earned: 100, hidden: true), false)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-22", goal: goal, earned: 101, hidden: false), false)
        tracker.resetBaseline()
        // Opening the app or editing a goal already achieved must not replay a celebration.
        checkEqual(tracker.shouldCelebrate(day: "2026-10-23", goal: goal, earned: 200, hidden: false), false)
        goal.amount = 250
        checkEqual(tracker.shouldCelebrate(day: "2026-10-23", goal: goal, earned: 249, hidden: false), false)
        checkEqual(tracker.shouldCelebrate(day: "2026-10-23", goal: goal, earned: 250, hidden: false), true)
    }
}

@main
enum SalaryEngineChecks {
    static func main() throws {
        let checks = SalaryEngineTests()
        let cases: [(String, () throws -> Void)] = [
            ("workday and lunch boundaries", checks.testWorkdayAndLunchBoundaries),
            ("weekend and midnight reset", checks.testWeekendAndDayReset),
            ("monthly conservation and reset", checks.testMonthlyConservationAndMonthReset),
            ("fixed basis, exact seconds and relaunch", checks.testFixedBasisAndExactElapsedSeconds),
            ("custom workdays and paid break", checks.testNoUnpaidBreakAndCustomWeekdays),
            ("overnight and calendar-day allocation", checks.testOvernightShiftAndCalendarDayAllocation),
            ("invalid inputs", checks.testInvalidInputsNeverProduceEarnings),
            ("settings persistence", checks.testSettingsRoundTrip),
            ("DST and monthly conservation", checks.testDSTUsesRealElapsedTimeAndMonthlyConservation),
            ("date overrides and independent pay bases", checks.testDayOverridesAndBothPayBases),
            ("overnight exceptions and overlap rejection", checks.testOvernightExceptionsAndConflictRejection),
            ("legacy migration and desktop persistence", checks.testLegacyMigrationAndDesktopPersistence),
            ("goal estimate through lunch and midnight", checks.testGoalEstimateSkipsBreakAndStopsAtMidnight),
            ("payday and local reminder plans", checks.testPaydayShortMonthAndReminderDates),
            ("goal celebration crossing, deduplication and privacy", checks.testGoalCelebratesOnlyOnCrossingAndRespectsPrivacy)
        ]
        for (name, check) in cases {
            try check()
            print("PASS: \(name)")
        }
        print("\(cases.count) checks passed.")
    }
}

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
            ("DST and monthly conservation", checks.testDSTUsesRealElapsedTimeAndMonthlyConservation)
        ]
        for (name, check) in cases {
            try check()
            print("PASS: \(name)")
        }
        print("\(cases.count) checks passed.")
    }
}

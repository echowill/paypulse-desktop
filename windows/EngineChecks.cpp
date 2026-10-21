#include "SalaryEngine.hpp"
#include <iostream>
#include <stdexcept>
#include <cstdlib>
using namespace paypulse;
std::time_t date(int y, int m, int d, int h = 0, int min = 0, int sec = 0) {
    std::tm t{}; t.tm_year = y - 1900; t.tm_mon = m - 1; t.tm_mday = d; t.tm_hour = h; t.tm_min = min; t.tm_sec = sec;
    return normalized(t);
}
void require(bool yes, const char* message) { if (!yes) throw std::runtime_error(message); }
void near(double a, double b) { require(std::abs(a - b) < 0.00001, "numeric mismatch"); }
int main() {
#ifdef _WIN32
    _putenv_s("TZ", "UTC"); _tzset();
#else
    setenv("TZ", "UTC", 1); tzset();
#endif
    Settings s; s.salary = 18400;
    auto get = [&](int d, int h, int m = 0, int sec = 0) { return snapshot(date(2026, 10, d, h, m, sec), s); };
    require(get(21, 8).state == State::waiting, "before work"); near(get(21, 8).today, 0);
    require(get(21, 9).state == State::working, "start boundary");
    require(get(21, 12).state == State::onBreak, "break boundary");
    near(get(21, 12).today, get(21, 12, 59, 59).today);
    require(get(21, 13).state == State::working, "return boundary");
    require(get(21, 18).state == State::finished, "end boundary"); near(get(21, 18).elapsed, 28800);
    near(get(21, 18).today, get(21, 23, 59, 59).today);
    require(get(24, 12).state == State::dayOff, "weekend"); near(get(22, 0).today, 0);
    near(get(31, 23, 59, 59).month, s.salary); require(get(31, 23).monthWorkdays == 22, "workday count");
    near(snapshot(date(2026, 11, 1), s).month, 0);
    std::cout << "PASS: boundaries, unpaid breaks, weekend, daily/monthly reset, month conservation\n";
    s.fixedBasis = true; s.fixedDays = 20; s.salary = 16000;
    near(get(21, 9).hourly, 100); near(get(21, 9, 0, 36).today, 1); near(get(21, 16).today, 600);
    std::cout << "PASS: fixed basis, exact seconds, fresh-process reconstruction\n";
    s.fixedBasis = false; s.start = 1320; s.end = 360; s.breakStart = 120; s.breakEnd = 180;
    require(s.error().empty(), "valid overnight");
    require(get(24, 1).state == State::working, "Friday continues Saturday");
    require(get(24, 2, 30).state == State::onBreak, "overnight break");
    near(get(24, 6).elapsed, 18000); require(get(25, 1).state == State::dayOff, "Sunday off");
    near(get(1, 1).elapsed, 3600); near(get(31, 23, 59, 59).month, s.salary);
    std::cout << "PASS: overnight, natural-day allocation, cross-month\n";
    s.salary = 0; require(!s.error().empty(), "zero salary rejected");
    s = Settings(); s.salary = 10000; s.weekdays = 0; require(!s.error().empty(), "empty workdays rejected");
    s.weekdays = 62; s.end = s.start; require(!s.error().empty(), "zero shift rejected");
    s = Settings(); s.salary = 10000; s.breakStart = 480; require(!s.error().empty(), "outside break rejected");
    s = Settings(); s.salary = 10000; s.fixedBasis = true; s.fixedDays = 0; require(!s.error().empty(), "zero fixed days rejected");
    s.fixedBasis = false; require(s.error().empty(), "inactive fixed field ignored");
    std::cout << "PASS: validation and inactive fields\nAll Windows-engine checks passed.\n";
}

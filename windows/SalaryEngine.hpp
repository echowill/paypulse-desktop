#pragma once
#include <algorithm>
#include <cmath>
#include <ctime>
#include <string>
#include <vector>

namespace paypulse {
struct Settings {
    double salary = 0;
    int start = 540, end = 1080;
    bool breakEnabled = true;
    int breakStart = 720, breakEnd = 780;
    unsigned weekdays = 62; // Sunday bit 0, Monday bit 1.
    bool fixedBasis = false;
    double fixedDays = 21.75;
    bool hidden = false, fourDecimals = false;
    int shiftMinutes() const { return (end - start + 1440) % 1440; }
    int breakOffset() const { return (breakStart - start + 1440) % 1440; }
    int breakMinutes() const { return (breakEnd - breakStart + 1440) % 1440; }
    int paidMinutes() const { return shiftMinutes() - (breakEnabled ? breakMinutes() : 0); }
    std::wstring error() const {
        if (!std::isfinite(salary) || salary <= 0 || salary > 100000000) return L"请输入大于 0、不超过 1 亿的月薪。";
        for (int n : {start, end, breakStart, breakEnd}) if (n < 0 || n >= 1440) return L"时间必须位于 00:00 至 23:59。";
        if (shiftMinutes() == 0) return L"上班与下班时间不能相同。";
        if (!weekdays || weekdays > 127) return L"请至少选择一个工作日。";
        if (breakEnabled && (breakOffset() == 0 || breakMinutes() == 0 || breakOffset() + breakMinutes() >= shiftMinutes())) return L"休息时段须完整位于上下班之间。跨夜班次的下班记为次日。";
        if (fixedBasis && (!std::isfinite(fixedDays) || fixedDays <= 0 || fixedDays > 31)) return L"固定月计薪天数须大于 0、不超过 31。";
        return L"";
    }
};
inline std::tm local(std::time_t t) {
    std::tm value{};
#ifdef _WIN32
    localtime_s(&value, &t);
#else
    localtime_r(&t, &value);
#endif
    return value;
}
inline std::time_t normalized(std::tm t) { t.tm_isdst = -1; return std::mktime(&t); }
inline std::time_t dayStart(std::time_t t) {
    auto d = local(t); d.tm_hour = d.tm_min = d.tm_sec = 0;
    return normalized(d);
}
inline std::time_t addDay(std::time_t t, int n) { auto d = local(t); d.tm_mday += n; return normalized(d); }
inline std::time_t at(std::time_t day, int minutes) {
    auto d = local(day); d.tm_mday += minutes / 1440; d.tm_hour = (minutes % 1440) / 60; d.tm_min = minutes % 60; d.tm_sec = 0;
    return normalized(d);
}
struct Interval { std::time_t start, end; };
struct Shift { Interval full; std::vector<Interval> paid; };
inline std::vector<Shift> shifts(std::time_t start, std::time_t end, const Settings& s) {
    std::vector<Shift> result;
    for (auto day = addDay(dayStart(start), -1); day < end; day = addDay(day, 1)) {
        if (!(s.weekdays & (1u << local(day).tm_wday))) continue;
        auto begin = at(day, s.start), finish = at(day, s.start + s.shiftMinutes());
        if (finish <= begin) continue;
        Shift shift{{begin, finish}, {}};
        if (s.breakEnabled) {
            auto b = at(day, s.start + s.breakOffset());
            auto e = at(day, s.start + s.breakOffset() + s.breakMinutes());
            if (b > begin) shift.paid.push_back({begin, std::min(b, finish)});
            if (e < finish) shift.paid.push_back({std::max(e, begin), finish});
        } else shift.paid.push_back(shift.full);
        result.push_back(shift);
    }
    return result;
}
inline double overlap(Interval interval, std::time_t begin, std::time_t end) {
    return std::max(0.0, std::difftime(std::min(interval.end, end), std::max(interval.start, begin)));
}
enum class State { unconfigured, working, onBreak, waiting, finished, dayOff };
struct Snapshot {
    double today = 0, month = 0, target = 0, hourly = 0, elapsed = 0, planned = 0;
    int monthWorkdays = 0;
    State state = State::unconfigured;
    std::time_t next = 0;
    std::wstring nextLabel;
    double progress() const { return planned > 0 ? std::clamp(elapsed / planned, 0.0, 1.0) : 0; }
};
inline std::wstring stateTitle(State state) {
    switch (state) {
        case State::working: return L"正在计薪";
        case State::onBreak: return L"休息时间";
        case State::waiting: return L"等待上班";
        case State::finished: return L"已下班";
        case State::dayOff: return L"今日休息";
        default: return L"尚未设置";
    }
}
inline Snapshot snapshot(std::time_t now, const Settings& s) {
    Snapshot r;
    if (!s.error().empty()) return r;
    auto today = dayStart(now), tomorrow = addDay(today, 1);
    auto m = local(today); m.tm_mday = 1;
    auto monthStart = normalized(m); m.tm_mon += 1;
    auto monthEnd = normalized(m);
    auto monthlyShifts = shifts(monthStart, monthEnd, s);
    double monthSeconds = 0, monthElapsed = 0;
    for (auto& shift : monthlyShifts) for (auto& p : shift.paid) {
        monthSeconds += overlap(p, monthStart, monthEnd);
        monthElapsed += overlap(p, monthStart, now);
    }
    double denominator = s.fixedBasis ? s.fixedDays * s.paidMinutes() * 60 : monthSeconds;
    double rate = denominator > 0 ? s.salary / denominator : 0;
    r.hourly = rate * 3600; r.month = monthElapsed * rate;
    for (auto d = monthStart; d < monthEnd; d = addDay(d, 1))
        if (s.weekdays & (1u << local(d).tm_wday)) ++r.monthWorkdays;
    auto dailyShifts = shifts(today, tomorrow, s);
    for (auto& shift : dailyShifts) for (auto& p : shift.paid) {
        r.planned += overlap(p, today, tomorrow);
        r.elapsed += overlap(p, today, now);
    }
    r.today = r.elapsed * rate; r.target = r.planned * rate;
    for (auto& shift : dailyShifts) {
        if (now >= shift.full.start && now < shift.full.end) {
            r.state = State::onBreak;
            for (auto& p : shift.paid) {
                if (now >= p.start && now < p.end) { r.state = State::working; break; }
                if (p.start > now) { r.next = p.start; r.nextLabel = L"休息结束"; break; }
            }
            if (r.state == State::working) { r.next = shift.full.end; r.nextLabel = L"距离下班"; }
            return r;
        }
    }
    for (auto& shift : dailyShifts) if (shift.full.start > now && shift.full.start < tomorrow) {
        r.state = State::waiting; r.next = shift.full.start; r.nextLabel = L"距离上班"; return r;
    }
    r.state = r.planned > 0 ? State::finished : State::dayOff;
    return r;
}
}

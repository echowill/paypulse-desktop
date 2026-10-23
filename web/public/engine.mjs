import { chinaCalendar } from './china-calendar.mjs?v=1.1.0';
export const chinaCalendarYears = Object.keys(chinaCalendar.years).map(Number);
export const hasChinaCalendar = (date) => Object.hasOwn(chinaCalendar.years, date.getFullYear());
export const chinaDay = (date) => chinaCalendar.years[date.getFullYear()]?.days[dayKey(date)];
export function defaults() {
  return {
    salary: { monthlySalary: 0, startMinute: 540, endMinute: 1080, breakEnabled: true,
      breakStartMinute: 720, breakEndMinute: 780, weekdays: [2, 3, 4, 5, 6], basis: 'calendar',
      fixedDays: 21.75, hideAmounts: false, showFourDecimals: false, dayOverrides: {} },
    desktop: { floating: { size: 'medium', font: 'rounded', appearance: 'system', content: 'amountAndCountdown' },
      goal: { enabled: false, name: '今天的小目标', amount: 100, celebrate: true },
      reminders: { offWorkEnabled: false, leadMinutes: 5, paydayEnabled: false, paydayDay: 10,
        paydayNotification: false, paydayMinute: 540 } },
  };
}
export const clone = (value) => structuredClone(value);
export const timeString = (minute) => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
export const dayKey = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
export const startOfDay = (date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());
export function addDays(date, count) { const result = new Date(date); result.setDate(result.getDate() + count); return result; }
export function dateFromKey(key) {
  if (typeof key !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(key)) return null;
  const [y, m, d] = key.split('-').map(Number);
  if (y < 1900 || y > 2200) return null;
  const date = new Date(y, m - 1, d);
  return dayKey(date) === key ? date : null;
}
export function hours(s) {
  return { startMinute: s.startMinute, endMinute: s.endMinute, breakEnabled: s.breakEnabled,
    breakStartMinute: s.breakStartMinute, breakEndMinute: s.breakEndMinute };
}
export const shiftMinutes = (h) => (h.endMinute - h.startMinute + 1440) % 1440;
export function breakOffsets(h) {
  const start = (h.breakStartMinute - h.startMinute + 1440) % 1440;
  return [start, start + (h.breakEndMinute - h.breakStartMinute + 1440) % 1440];
}
export const paidMinutes = (h) => shiftMinutes(h) - (h.breakEnabled ? (h.breakEndMinute - h.breakStartMinute + 1440) % 1440 : 0);
export function validateHours(h) {
  if (![h.startMinute, h.endMinute, h.breakStartMinute, h.breakEndMinute].every((v) => Number.isInteger(v) && v >= 0 && v < 1440)) return '请填写有效的上下班和休息时间。';
  if (!shiftMinutes(h)) return '上班和下班时间不能相同。';
  const [a, b] = breakOffsets(h);
  if (h.breakEnabled && !(a > 0 && b > a && b < shiftMinutes(h))) return '休息时段须完整位于上下班之间，且开始、结束时间不同。';
  return '';
}
export function workHours(date, s) {
  const override = s.dayOverrides?.[dayKey(date)];
  if (override) return override.isWorkingDay ? override.hours : null;
  if (s.basis === 'china') {
    if (!hasChinaCalendar(date)) return null;
    const special = chinaDay(date);
    return (special ? special.kind === 'work' : date.getDay() >= 1 && date.getDay() <= 5) ? hours(s) : null;
  }
  return s.weekdays.includes(date.getDay() + 1) ? hours(s) : null;
}
export const isPaidHoliday = (date, s) => s.basis === 'china' && !s.dayOverrides?.[dayKey(date)] && chinaDay(date)?.kind === 'statutory';
export const payHours = (date, s) => isPaidHoliday(date, s) ? hours(s) : workHours(date, s);
export function validateSalary(s) {
  if (!s || typeof s !== 'object') return '薪资设置数据无效。';
  if (!Number.isFinite(s.monthlySalary) || s.monthlySalary <= 0 || s.monthlySalary > 100_000_000) return '请输入大于 0、不超过 1 亿的月薪。';
  const error = validateHours(s); if (error) return error;
  if (!Array.isArray(s.weekdays) || (s.basis !== 'china' && !s.weekdays.length) || !s.weekdays.every((d) => Number.isInteger(d) && d >= 1 && d <= 7)) return '请至少选择一个常规工作日。';
  if (!['calendar', 'fixed', 'china'].includes(s.basis)) return '请选择计薪口径。';
  if (!Number.isFinite(s.fixedDays)) return '请填写有效的折算天数。';
  if (s.basis === 'fixed' && !(s.fixedDays > 0 && s.fixedDays <= 31)) return '固定折算天数须大于 0 且不超过 31。';
  if (!s.dayOverrides || typeof s.dayOverrides !== 'object' || Array.isArray(s.dayOverrides) || Object.keys(s.dayOverrides).length > 1000) return '临时排班数据无效。';
  const adjacent = new Map();
  for (const [key, override] of Object.entries(s.dayOverrides)) {
    const date = dateFromKey(key);
    if (!date || !override || typeof override.isWorkingDay !== 'boolean') return '临时排班含有无效日期或安排。';
    if (override.isWorkingDay) { const e = validateHours(override.hours ?? {}); if (e) return `${key}：${e}`; }
    adjacent.set(key, date); const previous = addDays(date, -1); adjacent.set(dayKey(previous), previous);
  }
  for (const [key, date] of adjacent) {
    const a = payHours(date, s), b = payHours(addDays(date, 1), s);
    if (a && b && a.startMinute + shiftMinutes(a) > 1440 + b.startMinute) return `${key} 的跨夜排班与次日重叠，请调整时间。`;
  }
  return '';
}
export function validateDesktop(d) {
  if (!d || !d.floating || !d.goal || !d.reminders) return '偏好设置数据无效。';
  const f = d.floating, g = d.goal, r = d.reminders;
  if (!['small', 'medium', 'large'].includes(f.size) || !['rounded', 'system', 'monospaced'].includes(f.font)
      || !['light', 'dark', 'system'].includes(f.appearance) || !['amount', 'amountAndCountdown'].includes(f.content)) return '请检查小窗外观设置。';
  if (g.enabled && (typeof g.name !== 'string' || !g.name.trim() || g.name.length > 24)) return '请填写 1 到 24 个字的目标名称。';
  if (!Number.isFinite(g.amount) || g.amount <= 0 || g.amount > 100_000_000) return '小目标金额须大于 0、不超过 1 亿。';
  if (!Number.isInteger(r.paydayDay) || r.paydayDay < 1 || r.paydayDay > 31 || !Number.isInteger(r.paydayMinute)
      || r.paydayMinute < 0 || r.paydayMinute >= 1440 || ![0, 5, 10, 15, 30].includes(r.leadMinutes)) return '请检查发薪日期和提醒时间。';
  return '';
}
function wallTime(day, minute) {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate() + Math.floor(minute / 1440), Math.floor((minute % 1440) / 60), minute % 60);
}
export function plannedShifts(start, end, s) {
  const result = [];
  for (let day = addDays(startOfDay(start), -1); day < end; day = addDays(day, 1)) {
    const h = payHours(day, s); if (!h) continue;
    const from = wallTime(day, h.startMinute), to = wallTime(day, h.startMinute + shiftMinutes(h));
    if (to <= from || to <= start || from >= end) continue;
    const paid = [];
    if (h.breakEnabled) {
      const [a, b] = breakOffsets(h), breakStart = wallTime(day, h.startMinute + a), breakEnd = wallTime(day, h.startMinute + b);
      if (Math.min(+breakStart, +to) > +from) paid.push([+from, Math.min(+breakStart, +to)]);
      if (+to > Math.max(+breakEnd, +from)) paid.push([Math.max(+breakEnd, +from), +to]);
    } else paid.push([+from, +to]);
    result.push({ workDate: day, start: +from, end: +to, paid, paidHoliday: isPaidHoliday(day, s) });
  }
  return result;
}
const overlap = (interval, start, end) => Math.max(0, Math.min(interval[1], +end) - Math.max(interval[0], +start)) / 1000;
export function snapshot(now, s) {
  const empty = { todayEarned: 0, monthEarned: 0, dailyTarget: 0, hourlyRate: 0, secondRate: 0, earnedSeconds: 0,
    plannedSeconds: 0, monthScheduledSeconds: 0, monthPaidSeconds: 0, rateDenominatorSeconds: 0, monthWorkdays: 0, monthPaidHolidays: 0, monthPayDays: 0, progress: 0, state: 'unconfigured', nextEvent: null, nextEventLabel: '', scheduleLabel: '等待你的排班' };
  if (validateSalary(s)) return empty;
  if (s.basis === 'china' && !hasChinaCalendar(now)) return { ...empty, state: 'calendarUnavailable', scheduleLabel: `${now.getFullYear()} 年计薪日历尚未收录，请切换计薪口径` };
  const today = startOfDay(now), tomorrow = addDays(today, 1);
  const month = new Date(now.getFullYear(), now.getMonth(), 1), nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const monthlyShifts = plannedShifts(month, nextMonth, s), monthly = monthlyShifts.flatMap((v) => v.paid);
  const daily = plannedShifts(today, tomorrow, s), paid = daily.flatMap((v) => v.paid);
  const monthSeconds = monthly.reduce((n, p) => n + overlap(p, month, nextMonth), 0);
  const denominator = s.basis === 'fixed' ? s.fixedDays * paidMinutes(s) * 60 : monthSeconds;
  const rate = denominator > 0 ? s.monthlySalary / denominator : 0;
  const earnedSeconds = paid.reduce((n, p) => n + overlap(p, today, now), 0);
  const plannedSeconds = paid.reduce((n, p) => n + overlap(p, today, tomorrow), 0);
  let monthWorkdays = 0, monthPaidHolidays = 0;
  for (let d = new Date(month); d < nextMonth; d = addDays(d, 1)) {
    if (workHours(d, s)) monthWorkdays++;
    if (isPaidHoliday(d, s)) monthPaidHolidays++;
  }
  const scheduledSeconds = monthlyShifts.filter(v => !v.paidHoliday).flatMap(v => v.paid).reduce((n, p) => n + overlap(p, month, nextMonth), 0);
  const result = { ...empty, todayEarned: earnedSeconds * rate, monthEarned: monthly.reduce((n, p) => n + overlap(p, month, now), 0) * rate,
    dailyTarget: plannedSeconds * rate, hourlyRate: rate * 3600, secondRate: rate, earnedSeconds, plannedSeconds,
    monthScheduledSeconds: scheduledSeconds, monthPaidSeconds: monthSeconds, rateDenominatorSeconds: denominator, monthWorkdays, monthPaidHolidays, monthPayDays: monthWorkdays + monthPaidHolidays, progress: plannedSeconds > 0 ? Math.min(1, earnedSeconds / plannedSeconds) : 0 };
  const active = daily.find((v) => +now >= v.start && +now < v.end);
  const next = daily.find((v) => v.start > +now && v.start < +tomorrow);
  if (active) {
    if (active.paid.some(([a, b]) => +now >= a && +now < b)) Object.assign(result, { state: active.paidHoliday ? 'paidHoliday' : 'working', nextEvent: active.end, nextEventLabel: active.paidHoliday ? '本段计薪结束' : '距离下班' });
    else Object.assign(result, { state: 'onBreak', nextEvent: active.paid.find(([a]) => a > +now)?.[0] ?? null, nextEventLabel: '休息结束' });
  } else if (next) Object.assign(result, { state: 'waiting', nextEvent: next.start, nextEventLabel: next.paidHoliday ? '带薪计时开始' : '距离上班' });
  else result.state = plannedSeconds > 0 ? 'finished' : 'dayOff';
  result.scheduleLabel = daily.length ? daily.map((v) => `${v.paidHoliday ? `${chinaDay(v.workDate)?.name} · 带薪休假 ` : ''}${v.start < +today ? '昨 ' : ''}${timeString(new Date(v.start).getHours() * 60 + new Date(v.start).getMinutes())} — ${timeString(new Date(v.end).getHours() * 60 + new Date(v.end).getMinutes())}${v.end >= +tomorrow ? ' 次日' : ''}`).join(' · ') : '今日休息';
  return result;
}
export function goalProgress(now, s, goal, supplied) {
  if (!goal.enabled || !(goal.amount > 0) || validateSalary(s)) return null;
  const current = supplied ?? snapshot(now, s), remaining = Math.max(0, goal.amount - current.todayEarned);
  if (current.state === 'calendarUnavailable') return null;
  const result = { fraction: Math.min(1, current.todayEarned / goal.amount), remaining, reached: remaining < 1e-7, workSeconds: null, completionDate: null };
  if (result.reached || current.secondRate <= 0) return result;
  const needed = remaining / current.secondRate;
  const tomorrow = addDays(startOfDay(now), 1);
  let left = needed;
  for (const interval of plannedShifts(now, tomorrow, s).flatMap((v) => v.paid).sort((a, b) => a[0] - b[0])) {
    const a = Math.max(+now, interval[0]), b = Math.min(+tomorrow, interval[1]);
    const seconds = Math.max(0, b - a) / 1000;
    if (left <= seconds + 1e-7) return { ...result, workSeconds: needed, completionDate: new Date(a + left * 1000) };
    left -= seconds;
  }
  return result;
}
export function nextPayday(after, day, minute = 540) {
  if (!Number.isInteger(day) || day < 1 || day > 31 || !Number.isInteger(minute) || minute < 0 || minute >= 1440) return null;
  for (let offset = 0; offset < 3; offset++) {
    const first = new Date(after.getFullYear(), after.getMonth() + offset, 1);
    const last = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
    const date = new Date(first.getFullYear(), first.getMonth(), Math.min(day, last), Math.floor(minute / 60), minute % 60);
    if (date >= after) return date;
  }
  return null;
}
export function reminderPlans(now, s, r) {
  if (validateSalary(s)) return [];
  const plans = [];
  if (r.offWorkEnabled) for (const shift of plannedShifts(now, addDays(startOfDay(now), 32), s)) {
    if (shift.paidHoliday) continue;
    const date = shift.end - r.leadMinutes * 60_000;
    if (date > +now && date >= shift.start) plans.push({ id: `offwork-${dayKey(shift.workDate)}`, date, kind: 'offWork' });
  }
  if (r.paydayEnabled && r.paydayNotification) {
    let after = now;
    for (let i = 0; i < 3; i++) {
      const date = nextPayday(after, r.paydayDay, r.paydayMinute); if (!date) break;
      plans.push({ id: `payday-${dayKey(date)}`, date: +date, kind: 'payday' }); after = new Date(+date + 1);
    }
  }
  return plans.sort((a, b) => a.date - b.date);
}
export const stateTitles = { unconfigured: '尚未设置', working: '正在计薪', paidHoliday: '带薪休假', calendarUnavailable: '日历待更新', onBreak: '休息时间', waiting: '等待计时', finished: '今日计薪结束', dayOff: '今日休息' };
export function countdown(seconds) {
  const s = Math.max(0, Math.ceil(seconds));
  return [Math.floor(s / 3600), Math.floor(s % 3600 / 60), s % 60].map((v) => String(v).padStart(2, '0')).join(':');
}

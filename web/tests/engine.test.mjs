import test from 'node:test';
import assert from 'node:assert/strict';
import { defaults, clone, snapshot, validateSalary, validateHours, validateDesktop, dateFromKey, dayKey,
  hours, goalProgress, nextPayday, reminderPlans, hasChinaCalendar, chinaDay, workHours } from '../public/engine.mjs';
process.env.TZ = 'Asia/Shanghai';
const date = (value) => new Date(value.replace(' ', 'T'));
const settings = () => ({ ...defaults().salary, monthlySalary: 18400 });
const snap = (value, s = settings()) => snapshot(date(value), s);
const near = (actual, expected, epsilon = 1e-6) => assert.ok(Math.abs(actual - expected) <= epsilon, `${actual} differs from ${expected}`);

test('China calendar has correct monthly work and paid day counts in both reviewed years', () => {
  const s = { ...settings(), basis: 'china', weekdays: [] };
  const expected = {
    2025: [[19,19,21,22,19,20,23,21,23,18,20,23], [24,19,21,23,22,20,23,21,23,22,20,23]],
    2026: [[21,16,22,21,19,21,23,21,22,18,21,23], [22,20,22,22,21,22,23,21,23,21,21,23]],
  };
  for (const [year, [work, paid]] of Object.entries(expected)) {
    let holidays = 0;
    for (let month = 1; month <= 12; month++) {
      const now = new Date(Number(year), month, 0, 23, 59, 59), current = snapshot(now, s);
      assert.equal(current.monthWorkdays, work[month - 1]); assert.equal(current.monthPayDays, paid[month - 1]);
      assert.equal(current.monthScheduledSeconds, work[month - 1] * 8 * 3600);
      assert.equal(current.monthPaidSeconds, paid[month - 1] * 8 * 3600);
      near(current.monthEarned, s.monthlySalary); holidays += current.monthPaidHolidays;
    }
    assert.equal(holidays, 13);
  }
});
test('statutory leave is paid once, regular rest is unpaid, makeup days work; corrected 2025 data is honored', () => {
  const s = { ...settings(), basis: 'china', monthlySalary: 16800 };
  const holiday = snap('2026-10-01 15:00:00', s);
  assert.equal(holiday.state, 'paidHoliday'); near(holiday.todayEarned, 500); near(holiday.hourlyRate, 100);
  assert.match(holiday.scheduleLabel, /国庆节 · 带薪休假/);
  assert.equal(workHours(date('2026-10-01 15:00:00'), s), null);
  assert.equal(snap('2026-10-01 12:30:00', s).state, 'onBreak');
  assert.equal(snap('2026-10-04 15:00:00', s).todayEarned, 0);
  assert.equal(snap('2026-10-10 15:00:00', s).state, 'working');
  assert.equal(chinaDay(date('2025-01-28 15:00:00')).kind, 'statutory');
  assert.equal(chinaDay(date('2025-10-06 15:00:00')).kind, 'statutory');
  assert.equal(chinaDay(date('2025-05-03 15:00:00')).kind, 'rest');
});
test('China mode manual overrides take priority without double paying or losing fixed-day independence', () => {
  const s = { ...settings(), basis: 'china', monthlySalary: 16800 };
  s.dayOverrides['2026-10-01'] = { isWorkingDay: true, hours: { ...hours(s), startMinute: 600, endMinute: 840, breakEnabled: false } };
  let current = snap('2026-10-01 14:00:00', s);
  assert.equal(current.monthWorkdays, 19); assert.equal(current.monthPaidHolidays, 2);
  assert.equal(current.monthPaidSeconds, 164 * 3600); assert.equal(current.earnedSeconds, 4 * 3600);
  s.dayOverrides['2026-10-01'] = { isWorkingDay: false };
  current = snap('2026-10-01 15:00:00', s);
  assert.equal(current.todayEarned, 0); assert.equal(current.monthPayDays, 20);
  delete s.dayOverrides['2026-10-01'];
  near(snap('2026-10-01 15:00:00', s).todayEarned, 500);
  s.monthlySalary *= 2;
  near(snap('2026-10-01 15:00:00', s).todayEarned, 1000);
  s.basis = 'fixed'; s.fixedDays = 21.75;
  assert.equal(snap('2026-10-01 15:00:00', s).monthWorkdays, 22);
  near(snap('2026-10-01 15:00:00', s).rateDenominatorSeconds, 21.75 * 8 * 3600);
});
test('paid leave skips off-work reminders and goals still skip lunch; missing years never invent dates', () => {
  const s = { ...settings(), basis: 'china', monthlySalary: 16800 };
  const r = { ...defaults().desktop.reminders, offWorkEnabled: true };
  const plans = reminderPlans(date('2026-10-01 10:00:00'), s, r);
  assert.equal(plans[0].id, 'offwork-2026-10-08');
  assert.ok(plans.some(p => p.id === 'offwork-2026-10-10'));
  const goal = { ...defaults().desktop.goal, enabled: true, amount: 350 };
  assert.equal(+goalProgress(date('2026-10-01 11:30:00'), s, goal).completionDate, +date('2026-10-01 13:30:00'));
  assert.equal(hasChinaCalendar(date('2027-01-01 10:00:00')), false);
  assert.equal(snap('2027-01-01 10:00:00', s).state, 'calendarUnavailable');
  assert.equal(snap('2027-01-01 10:00:00', s).monthEarned, 0);
  assert.equal(goalProgress(date('2027-01-01 10:00:00'), s, goal), null);
});
test('China overnight paid leave conserves monthly salary and rejects overlap with the next paid date', () => {
  const s = { ...settings(), basis: 'china', startMinute: 1320, endMinute: 360, breakEnabled: false };
  assert.equal(snap('2026-10-02 01:00:00', s).state, 'paidHoliday');
  near(snap('2026-10-31 23:59:59', s).monthEarned, s.monthlySalary);
  s.dayOverrides['2026-10-02'] = { isWorkingDay: true, hours: { ...hours(s), startMinute: 300, endMinute: 720 } };
  assert.match(validateSalary(s), /重叠/);
});

test('workday, lunch and end-of-day boundaries', () => {
  assert.equal(snap('2026-10-21 08:59:59').todayEarned, 0);
  assert.equal(snap('2026-10-21 09:00:00').state, 'working');
  assert.equal(snap('2026-10-21 12:00:00').state, 'onBreak');
  near(snap('2026-10-21 12:00:00').todayEarned, snap('2026-10-21 12:59:59').todayEarned);
  assert.equal(snap('2026-10-21 13:00:00').state, 'working');
  assert.equal(snap('2026-10-21 18:00:00').state, 'finished');
  assert.equal(snap('2026-10-21 18:00:00').earnedSeconds, 8 * 3600);
  near(snap('2026-10-21 18:00:00').progress, 1);
});
test('weekends, midnight and calendar month boundaries', () => {
  assert.equal(snap('2026-10-24 15:00:00').state, 'dayOff');
  assert.equal(snap('2026-10-22 00:00:00').todayEarned, 0);
  assert.equal(snap('2026-11-01 00:00:00').monthEarned, 0);
  near(snap('2026-10-31 23:59:59').monthEarned, 18400);
  assert.equal(snap('2026-10-21 15:00:00').monthWorkdays, 22);
});
test('fixed denominator, precise seconds and reopening without a running timer', () => {
  const s = { ...settings(), monthlySalary: 16000, basis: 'fixed', fixedDays: 20 };
  near(snap('2026-10-21 09:00:36', s).todayEarned, 1);
  near(snap('2026-10-21 16:00:00', s).todayEarned, 600);
  near(snap('2026-10-21 15:00:00', s).hourlyRate, 100);
  s.fixedDays = 21.75;
  assert.equal(snap('2026-10-21 15:00:00', s).monthWorkdays, 22);
});
test('paid lunch and custom weekdays', () => {
  const s = { ...settings(), breakEnabled: false, weekdays: [7] };
  assert.equal(snap('2026-10-24 12:30:00', s).state, 'working');
  assert.equal(snap('2026-10-24 18:00:00', s).earnedSeconds, 9 * 3600);
  assert.equal(snap('2026-10-21 12:30:00', s).state, 'dayOff');
});
test('salary and fixed days change the hourly divisor, while workday and time edits change actual schedule totals', () => {
  const s = { ...settings(), monthlySalary: 18000, startMinute: 510, endMinute: 1050, breakEndMinute: 810 };
  let current = snap('2026-10-21 15:00:00', s);
  assert.equal(current.monthWorkdays, 22);
  near(current.monthScheduledSeconds / 3600, 165);
  near(current.rateDenominatorSeconds / 3600, 165);
  near(current.hourlyRate, 18000 / 165);
  s.monthlySalary = 36000;
  current = snap('2026-10-21 15:00:00', s);
  near(current.hourlyRate, 36000 / 165);
  assert.equal(current.monthWorkdays, 22); near(current.monthScheduledSeconds / 3600, 165);
  s.basis = 'fixed'; s.fixedDays = 20;
  current = snap('2026-10-21 15:00:00', s);
  near(current.rateDenominatorSeconds / 3600, 150); near(current.hourlyRate, 240);
  assert.equal(current.monthWorkdays, 22); near(current.monthScheduledSeconds / 3600, 165);
  s.fixedDays = 15;
  current = snap('2026-10-21 15:00:00', s);
  near(current.rateDenominatorSeconds / 3600, 112.5); near(current.hourlyRate, 320);
  s.endMinute = 1110;
  current = snap('2026-10-21 15:00:00', s);
  near(current.monthScheduledSeconds / 3600, 187); near(current.rateDenominatorSeconds / 3600, 127.5);
  s.weekdays = [2, 3, 4, 5];
  current = snap('2026-10-21 15:00:00', s);
  assert.equal(current.monthWorkdays, 17); near(current.monthScheduledSeconds / 3600, 144.5);
});
test('overnight shifts are split by natural day, using the start weekday', () => {
  const s = { ...settings(), startMinute: 1320, endMinute: 360, breakStartMinute: 120, breakEndMinute: 180 };
  assert.equal(validateSalary(s), '');
  assert.equal(snap('2026-10-24 01:00:00', s).state, 'working');
  assert.equal(snap('2026-10-24 02:30:00', s).state, 'onBreak');
  assert.equal(snap('2026-10-24 06:00:00', s).earnedSeconds, 5 * 3600);
  assert.equal(snap('2026-10-25 01:00:00', s).state, 'dayOff');
  near(snap('2026-10-31 23:59:59', s).monthEarned, s.monthlySalary);
  assert.match(snap('2026-10-24 01:00:00', s).scheduleLabel, /^昨 22:00/);
});
test('date overrides affect actual hours; fixed days stay independent', () => {
  const s = settings(); s.dayOverrides['2026-10-21'] = { isWorkingDay: false };
  const short = { ...hours(s), startMinute: 600, endMinute: 840, breakEnabled: false };
  s.dayOverrides['2026-10-24'] = { isWorkingDay: true, hours: short };
  assert.equal(snap('2026-10-21 15:00:00', s).state, 'dayOff');
  assert.equal(snap('2026-10-24 14:00:00', s).monthWorkdays, 22);
  assert.equal(snap('2026-10-24 14:00:00', s).monthScheduledSeconds, 172 * 3600);
  near(snap('2026-10-31 23:59:59', s).monthEarned, s.monthlySalary);
  Object.assign(s, { monthlySalary: 16000, basis: 'fixed', fixedDays: 20 });
  near(snap('2026-10-24 14:00:00', s).todayEarned, 400);
  delete s.dayOverrides['2026-10-24'];
  assert.equal(snap('2026-10-24 14:00:00', s).state, 'dayOff');
});
test('reject overlapping adjacent shifts, allow exact boundaries', () => {
  const s = settings();
  s.dayOverrides['2026-10-23'] = { isWorkingDay: true, hours: { ...hours(s), startMinute: 1320, endMinute: 360, breakEnabled: false } };
  s.dayOverrides['2026-10-24'] = { isWorkingDay: true, hours: { ...hours(s), startMinute: 300, endMinute: 720, breakEnabled: false } };
  assert.match(validateSalary(s), /重叠/);
  s.dayOverrides['2026-10-24'].hours.startMinute = 360;
  assert.equal(validateSalary(s), '');
  s.dayOverrides['2026-10-24'] = { isWorkingDay: false };
  assert.equal(snap('2026-10-24 01:00:00', s).state, 'working');
});
test('goal estimate skips lunch and cannot extend past midnight', () => {
  const s = { ...settings(), monthlySalary: 16000, basis: 'fixed', fixedDays: 20 };
  const goal = { ...defaults().desktop.goal, enabled: true, amount: 350 };
  const p = goalProgress(date('2026-10-21 11:30:00'), s, goal);
  near(p.workSeconds, 3600); assert.equal(+p.completionDate, +date('2026-10-21 13:30:00'));
  assert.equal(goalProgress(date('2026-10-21 13:30:00'), s, goal).reached, true);
  goal.amount = 900;
  assert.equal(goalProgress(date('2026-10-21 15:00:00'), s, goal).completionDate, null);
  goal.amount = 50;
  assert.equal(+goalProgress(date('2026-10-22 00:00:00'), s, goal).completionDate, +date('2026-10-22 09:30:00'));
});
test('payday clamps short months and crosses the year correctly', () => {
  assert.equal(+nextPayday(date('2026-02-01 00:00:00'), 31), +date('2026-02-28 09:00:00'));
  assert.equal(+nextPayday(date('2028-02-01 00:00:00'), 31), +date('2028-02-29 09:00:00'));
  assert.equal(+nextPayday(date('2026-12-31 10:00:00'), 31), +date('2027-01-31 09:00:00'));
});
test('reminder plans honor off days, overnight overrides and unique identities', () => {
  const s = settings(), r = { ...defaults().desktop.reminders, offWorkEnabled: true, paydayEnabled: true, paydayNotification: true, paydayDay: 25 };
  s.dayOverrides['2026-10-22'] = { isWorkingDay: false };
  const plans = reminderPlans(date('2026-10-21 10:00:00'), s, r);
  assert.equal(plans[0].date, +date('2026-10-21 17:55:00'));
  assert.equal(plans.some((p) => p.id === 'offwork-2026-10-22'), false);
  assert.equal(new Set(plans.map((p) => p.id)).size, plans.length);
  s.dayOverrides['2026-10-23'] = { isWorkingDay: true, hours: { ...hours(s), startMinute: 1320, endMinute: 360, breakEnabled: false } };
  s.dayOverrides['2026-10-24'] = { isWorkingDay: false };
  assert.equal(reminderPlans(date('2026-10-24 01:00:00'), s, r)[0].date, +date('2026-10-24 05:55:00'));
});
test('invalid and corrupted data fail closed without producing earnings', () => {
  assert.ok(validateSalary(null)); assert.ok(validateSalary({}));
  assert.equal(snapshot(date('2026-10-21 15:00:00'), null).state, 'unconfigured');
  for (const patch of [{ monthlySalary: NaN }, { weekdays: [] }, { startMinute: 1080 }, { breakStartMinute: 480 }, { basis: 'fixed', fixedDays: 0 }]) {
    assert.ok(validateSalary({ ...settings(), ...patch }));
  }
  assert.ok(validateHours({ ...hours(settings()), startMinute: Infinity }));
  assert.equal(dateFromKey('2026-02-30'), null);
  assert.equal(dateFromKey('__proto__'), null);
  assert.equal(dayKey(dateFromKey('2026-02-28')), '2026-02-28');
});
test('all preferences and overrides survive JSON persistence', () => {
  const data = { version: 1, ...defaults() }; data.salary.monthlySalary = 18000;
  data.salary.dayOverrides['2026-10-24'] = { isWorkingDay: true, hours: hours(data.salary) };
  data.desktop.floating.appearance = 'dark'; data.desktop.goal.enabled = true;
  const restored = JSON.parse(JSON.stringify(data));
  assert.deepEqual(restored, data); assert.equal(validateSalary(restored.salary), ''); assert.equal(validateDesktop(restored.desktop), '');
});
test('DST uses actual elapsed seconds and conserves monthly salary', () => {
  const previous = process.env.TZ;
  try {
    process.env.TZ = 'America/New_York';
    const s = { ...settings(), startMinute: 0, endMinute: 480, breakEnabled: false, weekdays: [1, 2, 3, 4, 5, 6, 7] };
    assert.equal(snap('2026-03-08 08:00:00', s).earnedSeconds, 7 * 3600);
    assert.equal(snap('2026-11-01 08:00:00', s).earnedSeconds, 9 * 3600);
    near(snap('2026-03-31 23:59:59', s).monthEarned, s.monthlySalary);
  } finally { process.env.TZ = previous; }
});

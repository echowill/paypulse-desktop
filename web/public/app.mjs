import { defaults, clone, timeString, dayKey, startOfDay, dateFromKey, hours, paidMinutes, workHours, isPaidHoliday, chinaDay, hasChinaCalendar, chinaCalendarYears,
  validateHours, validateSalary, validateDesktop, snapshot, goalProgress, nextPayday, reminderPlans, stateTitles, countdown } from './engine.mjs?v=1.1.0';

const $ = (id) => document.getElementById(id);
const STORAGE = 'paypulse.web.v1';
const NOTICES = 'paypulse.web.notice-history';
const CELEBRATION = 'paypulse.web.goal-day';
const formatters = new Map([2, 4].map((n) => [n, new Intl.NumberFormat('en-US', { minimumFractionDigits: n, maximumFractionDigits: n })]));
const number = (n, digits = 2) => formatters.get(digits).format(n);
const money = (n, digits = 2, hidden = state.salary.hideAmounts) => hidden ? '••••' : number(n, digits);
const readNumber = (value) => Number(String(value).replace(/[,，\s]/g, ''));
const minute = (value) => /^\d\d:\d\d$/.test(value) ? Number(value.slice(0, 2)) * 60 + Number(value.slice(3)) : NaN;
function readLocal(key, fallback) { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } }
function writeLocal(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); return true; } catch { return false; } }
let state = readLocal(STORAGE, null);
if (!state || state.version !== 1 || validateSalary(state.salary) || validateDesktop(state.desktop)) state = { version: 1, ...defaults() };
let demo = false, draft = null, selectedTab = 'salary', pipWindow = null, previewWidget = null;
let overrideBaseline = '', lastGoal = null, goalPulse = false;
let lastCelebration = readLocal(CELEBRATION, '');
let noticeHistory = readLocal(NOTICES, []);
if (!Array.isArray(noticeHistory)) noticeHistory = [];
let lastReminderTick = Date.now(), plans = [], planDay = '';
let toastTimer;
const widget = $('widget'), widgetHome = $('widget-home');
widget.querySelectorAll('[id]').forEach((el) => { el.dataset.widget = el.id; });
const widgetNode = (root, id) => root.querySelector(`[data-widget="${id}"]`);
const systemDark = matchMedia('(prefers-color-scheme: dark)');
function text(id, value) { const node = $(id); const next = String(value); if (node.textContent !== next) node.textContent = next; }
function toast(message) { clearTimeout(toastTimer); text('toast', message); $('toast').hidden = false; toastTimer = setTimeout(() => { $('toast').hidden = true; }, 5000); }
function clockTime(date) { return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false }); }
function duration(seconds) { const m = Math.ceil(seconds / 60); return m < 60 ? `${m} 分钟` : `${Math.floor(m / 60)} 小时 ${m % 60} 分钟`; }
function countdownValue(now, current) {
  return current.nextEvent ? countdown((current.nextEvent - +now) / 1000) : current.state === 'unconfigured' ? '--:--:--' : current.state === 'dayOff' ? '好好生活' : '自由时间';
}
function applyWidgetStyle(root, options) {
  root.dataset.size = options.size; root.dataset.font = options.font;
  root.dataset.theme = options.appearance === 'dark' || (options.appearance === 'system' && systemDark.matches) ? 'dark' : 'light';
}
function renderWidget(root, config, current, now) {
  applyWidgetStyle(root, config.desktop.floating);
  widgetNode(root, 'widget-caption').textContent = goalPulse && root === widget ? '✓ 小目标达成' : '今日已赚';
  widgetNode(root, 'widget-state').textContent = stateTitles[current.state];
  widgetNode(root, 'widget-amount').textContent = `¥ ${money(current.todayEarned, config.salary.showFourDecimals ? 4 : 2, config.salary.hideAmounts)}`;
  widgetNode(root, 'widget-countdown-row').hidden = config.desktop.floating.content !== 'amountAndCountdown';
  widgetNode(root, 'widget-countdown-label').textContent = current.nextEventLabel || stateTitles[current.state];
  widgetNode(root, 'widget-countdown').textContent = countdownValue(now, current);
  if (root === widget && pipWindow && !pipWindow.closed) pipWindow.document.body.dataset.theme = root.dataset.theme;
}
function updateGoal(current, now) {
  const goal = state.desktop.goal, progress = goalProgress(now, state.salary, goal, current);
  $('goal-card').hidden = !progress;
  if (!progress) { lastGoal = null; return; }
  text('goal-title', goal.name); text('goal-amount', `¥${money(goal.amount)}`);
  $('goal-fill').style.width = `${progress.fraction * 100}%`;
  text('goal-icon', progress.reached ? '✓' : '⚑');
  let message;
  if (state.salary.hideAmounts) message = '金额已隐藏';
  else if (progress.reached) message = goalPulse ? '小目标达成，今天的努力值得庆祝！' : '今日目标已达成，明天再接再厉。';
  else if (progress.completionDate) message = `还需计薪 ${duration(progress.workSeconds)} · 预计 ${clockTime(progress.completionDate)} 达成`;
  else message = `还差 ¥${money(progress.remaining)} · 超出今日剩余排班可赚金额`;
  text('goal-message', message);
  const key = `${dayKey(now)}|${goal.name}|${goal.amount}`;
  if (lastGoal?.key === key && lastGoal.earned < goal.amount && current.todayEarned >= goal.amount
      && goal.celebrate && !state.salary.hideAmounts && lastCelebration !== dayKey(now)) {
    lastCelebration = dayKey(now); writeLocal(CELEBRATION, lastCelebration); goalPulse = true;
    $('goal-card').classList.add('celebrating'); toast('✓ 今天的小目标达成了！');
    setTimeout(() => { goalPulse = false; $('goal-card').classList.remove('celebrating'); update(); }, 5000);
  }
  lastGoal = { key, earned: current.todayEarned };
}
function refreshPlans(now = new Date()) {
  plans = reminderPlans(now, state.salary, state.desktop.reminders); planDay = dayKey(now); lastReminderTick = +now;
}
function checkReminders(now) {
  if (planDay !== dayKey(now)) refreshPlans(now);
  const before = lastReminderTick; lastReminderTick = +now;
  if (demo || !('Notification' in window) || Notification.permission !== 'granted' || +now < before || +now - before > 300_000) return;
  for (const plan of plans) {
    if (plan.date <= before || plan.date > +now || noticeHistory.includes(plan.id)) continue;
    const lead = state.desktop.reminders.leadMinutes;
    const title = plan.kind === 'payday' ? '今天是你设定的发薪日' : lead ? `还有 ${lead} 分钟下班` : '到下班时间了';
    const body = plan.kind === 'payday' ? '这是日期提醒，实际到账以工资发放为准。' : '按你的排班提醒。收好今天的努力，留些时间给自己。';
    try {
      const notice = new Notification(title, { body, tag: `paypulse-${plan.id}`, icon: new URL('./icon.svg', location.href).href });
      notice.onclick = () => { window.focus(); notice.close(); };
      noticeHistory = [...noticeHistory, plan.id].slice(-120); writeLocal(NOTICES, noticeHistory);
    } catch { /* The in-page clock remains usable if OS notification delivery is unavailable. */ }
  }
}
function update() {
  const now = new Date(), current = snapshot(now, state.salary), configured = !validateSalary(state.salary);
  text('today-date', now.toLocaleDateString('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' }));
  text('month-label', now.toLocaleDateString('zh-CN', { month: 'long' }));
  text('today-amount', money(current.todayEarned, state.salary.showFourDecimals ? 4 : 2));
  $('today-amount').parentElement.classList.toggle('four-decimals', state.salary.showFourDecimals);
  text('work-state', stateTitles[current.state]); $('state-badge').dataset.state = current.state;
  const messages = { working: `+ ¥${money(current.secondRate, 4)} / 秒，时间正在变成收入`, paidHoliday: '法定带薪节日，按常规时段分摊收入，安心休假。', calendarUnavailable: '本年日历尚未收录，请在设置中切换为实际排班或固定折算天数。', onBreak: '休息时间暂停累计，结束后自动继续计薪。',
    waiting: current.nextEventLabel === '带薪计时开始' ? '今天是法定带薪节日，常规时段内会自动累计收入。' : '上班时间一到，金额就会自动增长。', finished: '今天的收入已经记下，接下来是你的时间。', dayOff: '今天没有排班，把时间留给生活。', unconfigured: '设置月薪后，工作时段会自动计薪。' };
  text('earning-message', messages[current.state]);
  const pct = Math.floor(current.progress * 100);
  $('day-progress-fill').style.width = `${current.progress * 100}%`;
  $('day-progress-fill').parentElement.setAttribute('aria-valuenow', String(pct));
  text('day-progress-label', `今日进度 ${pct}%`); text('daily-target', `¥${money(current.dailyTarget)}`);
  text('hourly-rate', `¥${money(current.hourlyRate)}`); text('countdown-label', current.nextEventLabel || stateTitles[current.state]);
  text('countdown', countdownValue(now, current)); text('countdown-hint', current.state === 'paidHoliday' ? '按常规时段累计带薪收入' : current.nextEvent ? '按当天实际排班自动计薪' : '今天也有自己的节奏');
  text('month-amount', `¥${money(current.monthEarned)}`);
  text('month-schedule', configured ? `${current.monthWorkdays} 天 · ${number(current.monthScheduledSeconds / 3600)} 小时` : '填写后计算');
  $('month-pay-summary').hidden = state.salary.basis !== 'china';
  text('month-pay-summary', current.state === 'calendarUnavailable' ? messages.calendarUnavailable : `${current.monthWorkdays} 个工作日 + ${current.monthPaidHolidays} 个带薪节日 = ${current.monthPayDays} 个计薪日 · ${number(current.monthPaidSeconds / 3600)} 小时`);
  text('today-schedule', current.scheduleLabel);
  text('basis-label', state.salary.basis === 'china' ? '中国大陆计薪日历 · 按当月计薪时长分摊月薪' : state.salary.basis === 'calendar' ? '时薪按本月实际排班工时折算' : `时薪折算：${number(state.salary.fixedDays)} 天 / 月 × 常规班计薪时长`);
  $('payday-row').hidden = !state.desktop.reminders.paydayEnabled;
  if (state.desktop.reminders.paydayEnabled) {
    const date = nextPayday(startOfDay(now), state.desktop.reminders.paydayDay, state.desktop.reminders.paydayMinute);
    if (date) {
      const a = startOfDay(date), b = startOfDay(now);
      const days = Math.round((Date.UTC(a.getFullYear(), a.getMonth(), a.getDate()) - Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())) / 86_400_000);
      text('payday-label', days ? `距离发薪日还有 ${days} 天` : '今天是你设定的发薪日');
      text('payday-date', `${date.getMonth() + 1}/${date.getDate()}`);
    }
  }
  $('demo-banner').hidden = !demo; $('onboarding').hidden = configured;
  $('privacy').setAttribute('aria-label', state.salary.hideAmounts ? '显示金额' : '隐藏金额'); $('privacy-slash').hidden = !state.salary.hideAmounts;
  const supported = window.isSecureContext && 'documentPictureInPicture' in window;
  $('open-pip').disabled = !supported || !configured;
  if (!supported) text('pip-hint', '桌面小窗需要最新版电脑 Chrome。当前环境可使用网页计薪，暂时无法打开置顶小窗。');
  else if (!configured) text('pip-hint', '先设置工资或体验示例，再打开置顶小窗。');
  else text('pip-hint', '拖动标题栏移动小窗，拖动边缘调整大小。保留本页，小窗会一起计薪。');
  text('open-pip', pipWindow && !pipWindow.closed ? '↙ 收回桌面小窗' : '↗ 打开桌面小窗');
  updateGoal(current, now); renderWidget(widget, state, current, now); checkReminders(now);
  if ($('settings-dialog').open && selectedTab === 'appearance') renderAppearancePreview();
}

async function togglePip() {
  if (pipWindow && !pipWindow.closed) { pipWindow.close(); return; }
  if (!('documentPictureInPicture' in window) || validateSalary(state.salary)) return;
  try {
    const sizes = { small: [290, 135], medium: [340, 160], large: [400, 190] };
    const [width, height] = sizes[state.desktop.floating.size];
    // Request immediately inside the real click; Chrome requires user activation.
    const win = await window.documentPictureInPicture.requestWindow({ width, height });
    pipWindow = win; win.document.title = '薪跳 · 桌面小窗'; win.document.documentElement.lang = 'zh-CN';
    const css = win.document.createElement('link'); css.rel = 'stylesheet'; css.href = new URL('./styles.css?v=1.1.0', location.href).href; win.document.head.append(css);
    win.document.body.className = 'pip-body'; win.document.body.append(widget); $('widget-away').hidden = false;
    win.addEventListener('pagehide', () => {
      if (widget.ownerDocument === win.document) widgetHome.prepend(widget);
      if (pipWindow === win) pipWindow = null;
      $('widget-away').hidden = true; update();
    }, { once: true });
    update();
  } catch (error) {
    toast(error?.name === 'NotAllowedError' ? '请在电脑 Chrome 中亲自点击按钮打开小窗；浏览器策略也可能限制该功能。' : '小窗暂时没能打开，请更新电脑 Chrome 后再试。');
  }
}
function setTab(tab) {
  selectedTab = tab;
  document.querySelectorAll('[role=tab]').forEach((el) => { const on = el.dataset.tab === tab; el.setAttribute('aria-selected', String(on)); el.tabIndex = on ? 0 : -1; });
  document.querySelectorAll('[role=tabpanel]').forEach((el) => { el.hidden = el.id !== `panel-${tab}`; });
  document.querySelector('.settings-scroll').scrollTop = 0;
  if (tab === 'schedule' && draft && JSON.stringify(readOverride()) === overrideBaseline) loadOverride();
  if (tab === 'appearance') renderAppearancePreview();
}
function openSettings(tab = 'salary') {
  if ($('settings-dialog').open) { setTab(tab); return; }
  draft = clone(state); lastGoal = null; $('settings-error').hidden = true;
  fillForm(); setTab(tab); $('settings-dialog').showModal();
  if (tab === 'salary') $('salary-input').focus();
}
function closeSettings() { $('settings-dialog').close(); draft = null; previewWidget = null; }
function fillForm() {
  const s = draft.salary, d = draft.desktop;
  $('salary-input').value = s.monthlySalary > 0 ? String(s.monthlySalary) : '';
  for (const [id, value] of [['start-time', s.startMinute], ['end-time', s.endMinute], ['break-start', s.breakStartMinute], ['break-end', s.breakEndMinute]]) $(id).value = timeString(value);
  $('break-enabled').checked = s.breakEnabled; $('four-decimals').checked = s.showFourDecimals;
  document.querySelectorAll('[data-day]').forEach((el) => el.setAttribute('aria-pressed', String(s.weekdays.includes(Number(el.dataset.day)))));
  document.querySelectorAll('[name=basis]').forEach((el) => { el.checked = el.value === s.basis; });
  $('fixed-days').value = String(s.fixedDays);
  for (const field of ['size', 'content', 'font', 'appearance']) $(`floating-${field}`).value = d.floating[field];
  $('goal-enabled').checked = d.goal.enabled; $('goal-name').value = d.goal.name; $('goal-amount-input').value = String(d.goal.amount); $('goal-celebrate').checked = d.goal.celebrate;
  $('offwork-enabled').checked = d.reminders.offWorkEnabled; $('offwork-lead').value = String(d.reminders.leadMinutes);
  $('payday-enabled').checked = d.reminders.paydayEnabled; $('payday-day').value = String(d.reminders.paydayDay);
  $('payday-notification').checked = d.reminders.paydayNotification; $('payday-time').value = timeString(d.reminders.paydayMinute);
  $('override-date').value = dayKey(new Date()); loadOverride(); renderOverrideList(); updateForm();
}
function readDraft() {
  const s = draft.salary, d = draft.desktop;
  s.monthlySalary = readNumber($('salary-input').value);
  s.startMinute = minute($('start-time').value); s.endMinute = minute($('end-time').value);
  s.breakEnabled = $('break-enabled').checked; s.breakStartMinute = minute($('break-start').value); s.breakEndMinute = minute($('break-end').value);
  s.basis = document.querySelector('[name=basis]:checked')?.value || 'calendar';
  const fixed = readNumber($('fixed-days').value);
  s.fixedDays = s.basis !== 'fixed' && (!Number.isFinite(fixed) || fixed <= 0 || fixed > 31) ? 21.75 : fixed;
  s.showFourDecimals = $('four-decimals').checked;
  for (const field of ['size', 'content', 'font', 'appearance']) d.floating[field] = $(`floating-${field}`).value;
  d.goal.enabled = $('goal-enabled').checked; d.goal.name = $('goal-name').value.trim();
  d.goal.amount = readNumber($('goal-amount-input').value); d.goal.celebrate = $('goal-celebrate').checked;
  if (!d.goal.enabled && (!Number.isFinite(d.goal.amount) || d.goal.amount <= 0)) d.goal.amount = 100;
  Object.assign(d.reminders, { offWorkEnabled: $('offwork-enabled').checked, leadMinutes: Number($('offwork-lead').value),
    paydayEnabled: $('payday-enabled').checked, paydayDay: Number($('payday-day').value),
    paydayNotification: $('payday-notification').checked, paydayMinute: minute($('payday-time').value) });
}
function updateForm() {
  if (!draft) return;
  readDraft(); const s = draft.salary, d = draft.desktop;
  $('break-fields').hidden = !s.breakEnabled; $('overnight-note').hidden = !(s.endMinute < s.startMinute);
  $('fixed-days-row').hidden = s.basis !== 'fixed'; $('preview-denominator-row').hidden = s.basis !== 'fixed';
  text('basis-explanation', s.basis === 'china' ? '月薪 ÷ 本月计薪时长。法定带薪节日按常规时段（含休息扣除）累计，调休休息日不重复计薪，完整月份累计等于月薪。这是收入展示分摊方式；法定日工资折算可选固定 21.75 天，不自动计算加班费。' : s.basis === 'calendar' ? '月薪 ÷ 本月实际排班工时。临时安排也计入分母，完整排班月的预估收入等于月薪。' : '折算天数只影响时薪，不改变实际排班。分母使用常规班计薪时长；临时班次按实际时长累计，月累计可能与月薪不同。');
  const china = s.basis === 'china';
  document.querySelectorAll('[data-day]').forEach(el => { el.disabled = china; });
  text('weekday-note', china ? '使用全国双休及调休安排，工作日按钮暂不参与。企业特殊安排可在「临时排班」覆盖。' : '绿色为常规工作日。特殊日期在「临时排班」中单独修改。');
  $('china-calendar-info').hidden = !china;
  text('china-calendar-status', hasChinaCalendar(new Date()) ? `已载入 ${new Date().getFullYear()} 年日历 · 已核对，离线可用` : '本年日历尚未收录，请切换为实际排班或固定折算天数。');
  text('china-calendar-years', `已收录 ${chinaCalendarYears.join('、')} 年。手动安排优先；带薪节日不发下班提醒。`);
  // Actual scheduled time is independent of salary and the chosen pay divisor.
  const schedule = { ...clone(s), monthlySalary: 1, basis: china ? 'china' : 'calendar', fixedDays: 21.75 };
  const now = new Date(), scheduleValid = !validateSalary(schedule), actual = snapshot(now, schedule);
  text('preview-schedule', scheduleValid ? `${actual.monthWorkdays} 天 · ${number(actual.monthScheduledSeconds / 3600)} 小时` : '填写完整的工作日与时段后计算');
  $('preview-pay-calendar').hidden = !china;
  text('preview-pay-calendar', actual.state === 'calendarUnavailable' ? '日历尚未收录，暂不计算收入' : `${actual.monthWorkdays} 个工作日 + ${actual.monthPaidHolidays} 个带薪节日 = ${actual.monthPayDays} 个计薪日`);
  const divisorSettings = { ...clone(s), monthlySalary: 1 };
  const divisorValid = !validateSalary(divisorSettings), divisor = snapshot(now, divisorSettings);
  const divisorHours = divisor.rateDenominatorSeconds / 3600;
  const salaryValid = !validateSalary(s), current = snapshot(now, s);
  text('preview-hours-label', china ? '本月计薪时长（含带薪节日）' : s.basis === 'calendar' ? '本月排班计薪工时' : '固定折算计薪工时');
  text('preview-pay-hours', divisorValid ? `${number(divisorHours)} 小时` : '填写后计算');
  text('preview-denominator', divisorValid ? `${number(s.fixedDays)} 天 × ${number(paidMinutes(s) / 60)} 小时 / 天` : '填写后计算');
  text('preview-salary', Number.isFinite(s.monthlySalary) && s.monthlySalary > 0 ? `¥ ${number(s.monthlySalary)}` : '填写后计算');
  text('preview-rate', salaryValid && divisorHours > 0 ? `¥ ${number(current.hourlyRate)} / 小时` : '暂无法折算');
  text('preview-formula', salaryValid && divisorHours > 0
    ? `¥ ${number(s.monthlySalary)} ÷ ${number(divisorHours)} 小时 = ¥ ${number(current.hourlyRate)} / 小时`
    : divisorValid && divisorHours === 0 ? '本月未安排计薪工时，请调整排班后计算时薪。' : '填写月薪和排班后，这里会实时显示计算公式。');
  $('goal-fields').hidden = !d.goal.enabled; $('offwork-fields').hidden = !d.reminders.offWorkEnabled;
  $('payday-fields').hidden = !d.reminders.paydayEnabled; $('payday-time-row').hidden = !d.reminders.paydayNotification;
  const status = !('Notification' in window) ? '当前浏览器无法发送系统通知。' : Notification.permission === 'granted' ? '浏览器通知已允许，通知中不显示工资金额。' : Notification.permission === 'denied' ? '浏览器通知未获允许。可在地址栏的网站设置中开启，再保存。' : '开启提醒并保存后，将申请浏览器通知权限。';
  text('notification-status', status);
  $('override-work-fields').hidden = document.querySelector('[name=override-working]:checked')?.value !== 'yes';
  $('override-break-fields').hidden = !$('override-break-enabled').checked;
  if (selectedTab === 'appearance') renderAppearancePreview();
}
function renderAppearancePreview() {
  if (!draft) return;
  if (!previewWidget) {
    previewWidget = widget.cloneNode(true); previewWidget.removeAttribute('id');
    previewWidget.querySelectorAll('[id]').forEach((el) => el.removeAttribute('id'));
    previewWidget.inert = true; previewWidget.setAttribute('aria-hidden', 'true'); $('appearance-preview').replaceChildren(previewWidget);
  }
  renderWidget(previewWidget, draft, snapshot(new Date(), draft.salary), new Date());
}
function readOverride() {
  return { isWorkingDay: document.querySelector('[name=override-working]:checked')?.value === 'yes',
    hours: { startMinute: minute($('override-start').value), endMinute: minute($('override-end').value), breakEnabled: $('override-break-enabled').checked,
      breakStartMinute: minute($('override-break-start').value), breakEndMinute: minute($('override-break-end').value) } };
}
function loadOverride() {
  const date = dateFromKey($('override-date').value); if (!date) return;
  const stored = draft.salary.dayOverrides[dayKey(date)], h = stored?.hours ?? hours(draft.salary);
  const working = stored ? stored.isWorkingDay : !!workHours(date, draft.salary);
  document.querySelectorAll('[name=override-working]').forEach((el) => { el.checked = (el.value === 'yes') === working; });
  for (const [id, value] of [['override-start', h.startMinute], ['override-end', h.endMinute], ['override-break-start', h.breakStartMinute], ['override-break-end', h.breakEndMinute]]) $(id).value = timeString(value);
  $('override-break-enabled').checked = h.breakEnabled; overrideBaseline = JSON.stringify(readOverride());
  text('override-auto-info', isPaidHoliday(date, draft.salary) ? `当前自动安排：${chinaDay(date)?.name} · 带薪休假。加入休息覆盖后不再计薪。` : '手动安排保存后覆盖此日的自动规则。');
  text('override-message', ''); updateForm();
}
function overrideError(override, key) {
  if (!dateFromKey(key)) return '请选择有效的排班日期。';
  if (override.isWorkingDay) { const error = validateHours(override.hours); if (error) return error; }
  const test = clone(draft.salary); test.monthlySalary = Math.max(1, test.monthlySalary || 0); test.dayOverrides[key] = override;
  return validateSalary(test);
}
function showError(message) { text('settings-error', message); $('settings-error').hidden = false; }
function addOverride() {
  readDraft(); const override = readOverride(), key = $('override-date').value, error = overrideError(override, key);
  if (error) { showError(error); return; }
  draft.salary.dayOverrides[key] = override; overrideBaseline = JSON.stringify(override); $('settings-error').hidden = true;
  renderOverrideList(); updateForm(); text('override-message', `已加入 ${key}，点击底部「保存设置」生效。`);
}
function renderOverrideList() {
  const keys = Object.keys(draft.salary.dayOverrides).sort(), list = $('override-list'); list.replaceChildren(); text('override-count', keys.length);
  if (!keys.length) { const p = document.createElement('p'); p.className = 'fineprint'; p.textContent = '还没有临时安排。调休、补班或临时改时段，都可以在上方添加。'; list.append(p); }
  for (const key of keys) {
    const override = draft.salary.dayOverrides[key], row = document.createElement('div'); row.className = 'override-row';
    const details = document.createElement('div'), title = document.createElement('strong'), desc = document.createElement('small');
    title.textContent = key; const h = override.hours;
    desc.textContent = override.isWorkingDay ? `${timeString(h.startMinute)} — ${timeString(h.endMinute)}${h.endMinute < h.startMinute ? ' 次日' : ''}` : '休息（不计薪）';
    details.append(title, desc);
    const edit = document.createElement('button'); edit.type = 'button'; edit.textContent = '编辑'; edit.addEventListener('click', () => { $('override-date').value = key; loadOverride(); });
    const restore = document.createElement('button'); restore.type = 'button'; restore.textContent = '恢复自动安排'; restore.addEventListener('click', () => {
      delete draft.salary.dayOverrides[key]; renderOverrideList(); if ($('override-date').value === key) loadOverride();
      updateForm(); text('override-message', `${key} 已恢复自动安排，保存后生效。`);
    }); row.append(details, edit, restore); list.append(row);
  }
}
async function saveSettings(event) {
  event.preventDefault(); readDraft();
  const override = readOverride();
  if (JSON.stringify(override) !== overrideBaseline) {
    const key = $('override-date').value, error = overrideError(override, key); if (error) { setTab('schedule'); showError(error); return; }
    draft.salary.dayOverrides[key] = override;
  }
  const error = validateSalary(draft.salary) || validateDesktop(draft.desktop);
  if (error) { showError(error); return; }
  state = clone(draft); state.version = 1; demo = false; lastGoal = null; goalPulse = false;
  const saved = writeLocal(STORAGE, state), needNotifications = state.desktop.reminders.offWorkEnabled || (state.desktop.reminders.paydayEnabled && state.desktop.reminders.paydayNotification);
  renderWidget(widget, state, snapshot(new Date(), state.salary), new Date());
  if (pipWindow && !pipWindow.closed) { const sizes = { small: [290, 135], medium: [340, 160], large: [400, 190] }; try { pipWindow.resizeTo(...sizes[state.desktop.floating.size]); } catch { /* Can also resize using the window edge. */ } }
  closeSettings(); refreshPlans(); update();
  if (needNotifications && 'Notification' in window && Notification.permission === 'default') {
    try { await Notification.requestPermission(); } catch { toast('通知权限未完成，可在网站设置中允许通知。'); return; }
  }
  toast(saved ? '设置已保存，跟着你的节奏计薪。' : '当前页面已生效，但浏览器阻止了本地保存；关闭后可能需要重新设置。');
}

for (const button of document.querySelectorAll('[data-tab]')) button.addEventListener('click', () => { updateForm(); setTab(button.dataset.tab); });
const tabs = [...document.querySelectorAll('[role=tab]')];
tabs.forEach((tab, index) => tab.addEventListener('keydown', (event) => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault(); const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
  setTab(tabs[next].dataset.tab); tabs[next].focus();
}));
document.querySelectorAll('[data-day]').forEach((button) => button.addEventListener('click', () => {
  const day = Number(button.dataset.day), set = new Set(draft.salary.weekdays);
  if (set.has(day)) set.delete(day); else set.add(day);
  draft.salary.weekdays = [...set]; button.setAttribute('aria-pressed', String(set.has(day))); updateForm();
}));
document.querySelectorAll('[data-goal]').forEach((button) => button.addEventListener('click', () => {
  const presets = { coffee: ['咖啡', 20], lunch: ['午饭', 40], daily: ['今天的小目标', 100] }, [name, amount] = presets[button.dataset.goal];
  $('goal-name').value = name; $('goal-amount-input').value = String(amount); updateForm();
}));
$('settings-form').addEventListener('input', updateForm); $('settings-form').addEventListener('change', updateForm);
$('settings-form').addEventListener('submit', saveSettings);
$('override-date').addEventListener('change', loadOverride); $('add-override').addEventListener('click', addOverride);
$('close-settings').addEventListener('click', closeSettings); $('cancel-settings').addEventListener('click', closeSettings);
$('settings-dialog').addEventListener('cancel', () => { draft = null; previewWidget = null; });
$('settings-top').addEventListener('click', () => openSettings()); $('start-settings').addEventListener('click', () => openSettings());
$('demo-edit').addEventListener('click', () => openSettings()); $('schedule-shortcut').addEventListener('click', () => openSettings('schedule'));
$('appearance-shortcut').addEventListener('click', () => openSettings('appearance'));
$('widget-settings').addEventListener('click', () => { window.focus(); openSettings('appearance'); });
$('open-pip').addEventListener('click', togglePip); $('close-pip').addEventListener('click', () => pipWindow?.close());
$('privacy').addEventListener('click', () => { state.salary.hideAmounts = !state.salary.hideAmounts; lastGoal = null; goalPulse = false; if (!demo && !validateSalary(state.salary)) writeLocal(STORAGE, state); update(); });
$('try-demo').addEventListener('click', () => {
  state = { version: 1, ...defaults() }; state.salary.monthlySalary = 18000;
  state.desktop.goal.enabled = true; state.desktop.goal.name = '今日小目标'; state.desktop.goal.amount = 600;
  state.desktop.reminders.paydayEnabled = true; state.desktop.reminders.paydayDay = 25;
  demo = true; lastGoal = null; refreshPlans(); update(); toast('已使用演示工资，仅供体验，不自动保存。');
});
$('help-button').addEventListener('click', () => $('help-dialog').showModal()); $('close-help').addEventListener('click', () => $('help-dialog').close());
for (let day = 1; day <= 31; day++) { const option = document.createElement('option'); option.value = String(day); option.textContent = `${day} 日`; $('payday-day').append(option); }
systemDark.addEventListener('change', update); document.addEventListener('visibilitychange', update); window.addEventListener('pageshow', update);
window.addEventListener('storage', (event) => {
  if (event.key !== STORAGE || $('settings-dialog').open) return;
  const next = readLocal(STORAGE, null); if (next && !validateSalary(next.salary) && !validateDesktop(next.desktop)) { state = next; demo = false; lastGoal = null; refreshPlans(); update(); }
});
refreshPlans(); update(); setInterval(update, 1000);

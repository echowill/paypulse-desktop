import AppKit
import SwiftUI
import PayPulseCore

enum SettingsTab: String, CaseIterable {
    case salary = "薪资排班", appearance = "浮窗外观", goals = "目标提醒", schedule = "临时排班"
}

struct SettingsView: View {
    // Keep this editor independent of the model's one-second publisher. Its draft,
    // field editors and IME composition must survive every live clock refresh.
    let model: AppModel
    var height: CGFloat = 700
    var onSave: () -> Void
    var onCancel: () -> Void
    @State private var draft: SalarySettings
    @State private var desktop: DesktopPreferences
    @State private var salaryText: String
    @State private var fixedDaysText: String
    @State private var goalAmountText: String
    @State private var selectedTab: SettingsTab
    @State private var error = ""
    @State private var loginEnabled: Bool
    @State private var overrideDate: Date
    @State private var overrideWorking = true
    @State private var overrideHours = WorkHours()
    @State private var overrideBaseline = DayOverride(isWorkingDay: true)
    @State private var overrideMessage = ""
    @FocusState private var salaryFocused: Bool

    init(model: AppModel, height: CGFloat = 700, tab: SettingsTab = .salary,
         onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model; self.height = height; self.onSave = onSave; self.onCancel = onCancel
        _draft = State(initialValue: model.settings)
        _desktop = State(initialValue: model.desktop)
        _salaryText = State(initialValue: model.settings.monthlySalary > 0 ? String(format: "%.2f", model.settings.monthlySalary) : "")
        _fixedDaysText = State(initialValue: String(format: "%.2f", model.settings.fixedDays))
        _goalAmountText = State(initialValue: String(format: "%.2f", model.desktop.goal.amount))
        _loginEnabled = State(initialValue: model.launchAtLogin)
        _selectedTab = State(initialValue: tab)
        _overrideDate = State(initialValue: model.now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text("让收入跟上你的节奏").font(.system(size: 21, weight: .semibold))
                    Text("薪资、桌面小窗和每天的小期待，都在这里。").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
            Picker("设置分类", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 28).padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .salary: salaryPage
                    case .appearance: appearancePage
                    case .goals: goalsPage
                    case .schedule: schedulePage
                    }
                }.padding(.horizontal, 28).padding(.top, 3).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 9) {
                if !error.isEmpty {
                    Text(error).font(.system(size: 11)).foregroundColor(Color(red: 0.70, green: 0.20, blue: 0.16))
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button("取消") { onCancel() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                    Button(model.configured ? "保存设置" : "保存并开始计薪") { save() }
                        .buttonStyle(SoftButton(primary: true)).keyboardShortcut(.defaultAction)
                }
            }.padding(.horizontal, 28).padding(.vertical, 16).background(Theme.paper)
        }.frame(width: 620, height: height).background(Theme.paper).foregroundColor(Theme.ink)
            .tint(Theme.green).accentColor(Theme.green).preferredColorScheme(.light)
            .onAppear { loadOverride(); if selectedTab == .salary { DispatchQueue.main.async { salaryFocused = true } } }
            .onChange(of: selectedTab) { tab in
                error = ""
                if tab == .schedule, DayOverride(isWorkingDay: overrideWorking, hours: overrideHours) == overrideBaseline { loadOverride() }
            }
    }

    private var salaryPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                title("01", "你的月薪")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("¥").font(.system(size: 24, weight: .light)).foregroundColor(Theme.green)
                    TextField("例如 15000", text: $salaryText).textFieldStyle(.plain)
                        .font(.system(size: 32, weight: .medium, design: .rounded)).focused($salaryFocused).accessibilityLabel("月工资")
                    Text("元 / 月").font(.system(size: 11)).foregroundColor(Theme.muted)
                }.padding(16).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
                note("可填税前或到手月薪，展示口径与你的输入一致。")
            }
            VStack(alignment: .leading, spacing: 12) {
                title("02", "常规工作与休息")
                WorkHoursEditor(hours: Binding(get: { draft.hours }, set: { draft.hours = $0 }))
                HStack(spacing: 7) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Button {
                            if draft.weekdays.contains(day) { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                        } label: {
                            Text(weekday(day)).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).frame(height: 34)
                                .foregroundColor(draft.weekdays.contains(day) ? .white : Theme.muted)
                                .background(draft.weekdays.contains(day) ? Theme.green : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(draft.basis == .china).accessibilityLabel("周\(weekday(day))，\(draft.weekdays.contains(day) ? "已选" : "未选")")
                    }
                }
                note(draft.basis == .china ? "使用全国双休及调休安排，工作日按钮暂不参与。企业特殊安排可在「临时排班」覆盖。" : "绿色为常规工作日。个别日期可在「临时排班」中改为上班或休息。")
            }
            VStack(alignment: .leading, spacing: 12) {
                title("03", "计薪口径")
                Picker("计薪口径", selection: $draft.basis) {
                    Text("中国大陆计薪日历").tag(PayBasis.china)
                    Text("按本月实际排班").tag(PayBasis.calendar)
                    Text("固定折算天数").tag(PayBasis.fixed)
                }.pickerStyle(.segmented).labelsHidden()
                if draft.basis == .china {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ChinaCalendar.status(at: model.now)).fontWeight(.medium)
                        Text("已收录 \(ChinaCalendar.years.map(String.init).joined(separator: "、")) 年。手动安排优先；带薪节日不发下班提醒。")
                        Link("数据来源：Timor ↗", destination: URL(string: "https://timor.tech/api/holiday/")!)
                    }.font(.system(size: 11)).foregroundColor(Theme.green).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Theme.green.opacity(0.06)).cornerRadius(10)
                }
                if draft.basis == .fixed {
                    HStack {
                        Text("每月折算天数").font(.system(size: 12))
                        Spacer()
                        TextField("21.75", text: $fixedDaysText).textFieldStyle(.roundedBorder).frame(width: 90).accessibilityLabel("每月折算天数")
                        Text("天 / 月").font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
                VStack(spacing: 12) {
                    infoRow("本月实际排班", "\(previewSnapshot.monthWorkdays) 天 · \(AppModel.number(previewSnapshot.monthScheduledSeconds / 3600, digits: 1)) 小时")
                    if draft.basis == .china {
                        infoRow("本月计薪日", "\(previewSnapshot.monthWorkdays) 工作日 + \(previewSnapshot.monthPaidHolidays) 带薪节日 = \(previewSnapshot.monthPayDays) 天")
                        infoRow("计薪时长（含带薪节日）", "\(AppModel.number(previewSnapshot.monthPaidSeconds / 3600, digits: 1)) 小时")
                    }
                    if draft.basis == .fixed { infoRow("时薪折算分母", "\(fixedDaysText) 天 × \(AppModel.number(Double(draft.paidMinutes) / 60, digits: 2)) 小时 / 天") }
                    infoRow("折合时薪", parsedDraft.validationError == nil ? "¥ \(AppModel.number(previewSnapshot.hourlyRate)) / 小时" : "填写后计算")
                }.padding(14).background(Theme.green.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                note(draft.basis == .china ? "按本月计薪时长分摊月薪，完整月份累计等于月薪。法定带薪节日沿用常规时段与休息扣除，这只是收入展示时段，不要求当天上班。不自动计算加班费；固定 21.75 天折算仍可单独选择。" : draft.basis == .calendar
                     ? "月薪 ÷ 本月实际排班工时。临时排班也计入分母，完整排班月的预估收入等于月薪。"
                     : "折算天数只影响时薪，不会改变实际排班天数。固定口径使用常规班计薪时长，临时班次按其实际时长计薪，月累计可能与月薪不同。")
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("今日金额显示 4 位小数", isOn: $draft.showFourDecimals)
                Toggle("登录 Mac 时自动启动", isOn: $loginEnabled).disabled(model.preview)
                note("薪资只保存在本机。修改工资和排班会回算今天及本月预估收入；不保存历史工资版本。")
            }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
        }
    }

    private var appearancePage: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                title("01", "桌面预览")
                HStack {
                    Spacer()
                    FloatingWidget(preferences: desktop.floating,
                                   amount: "¥ \(model.amount(previewSnapshot.todayEarned, digits: draft.showFourDecimals ? 4 : 2))",
                                   state: previewSnapshot.state, countdownLabel: previewSnapshot.nextEventLabel, countdown: model.countdown)
                    Spacer()
                }.padding(.vertical, 25).background(Theme.line.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 14))
                note("保存后应用到桌面小窗。拖动可移动，双击可打开设置。")
            }
            VStack(alignment: .leading, spacing: 18) {
                title("02", "外观与内容")
                Picker("小窗大小", selection: $desktop.floating.size) {
                    Text("小").tag(FloatingSize.small); Text("中").tag(FloatingSize.medium); Text("大").tag(FloatingSize.large)
                }.pickerStyle(.segmented)
                Picker("显示内容", selection: $desktop.floating.content) {
                    Text("今日收入").tag(FloatingContent.amount)
                    Text("收入 + 倒计时").tag(FloatingContent.amountAndCountdown)
                }.pickerStyle(.segmented)
                Picker("数字字体", selection: $desktop.floating.font) {
                    Text("圆润").tag(FloatingFont.rounded); Text("系统").tag(FloatingFont.system); Text("等宽").tag(FloatingFont.monospaced)
                }.pickerStyle(.segmented)
                Picker("小窗主题", selection: $desktop.floating.appearance) {
                    Text("跟随系统").tag(FloatingAppearance.system); Text("浅色").tag(FloatingAppearance.light); Text("深色").tag(FloatingAppearance.dark)
                }.pickerStyle(.segmented)
                HStack {
                    Text("背景不透明度")
                    Slider(value: $desktop.floating.backgroundOpacity, in: 0.5...1, step: 0.05).accessibilityLabel("背景不透明度")
                    Text("\(Int((desktop.floating.backgroundOpacity * 100).rounded()))%").monospacedDigit().frame(width: 40)
                }
                note("仅背景改变透明度，数字保持清晰。小窗位置会记住，换屏后自动移回可见区域。")
            }.font(.system(size: 12))
        }
    }

    private var goalsPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                title("01", "每天一个收入小目标")
                Toggle("启用今日小目标", isOn: $desktop.goal.enabled)
                if desktop.goal.enabled {
                    HStack(spacing: 8) {
                        preset("咖啡", amount: 20); preset("午饭", amount: 40); preset("今天的小目标", amount: 100)
                    }
                    HStack {
                        TextField("目标名称", text: $desktop.goal.name).textFieldStyle(.roundedBorder).accessibilityLabel("目标名称")
                        Text("¥")
                        TextField("100", text: $goalAmountText).textFieldStyle(.roundedBorder).frame(width: 100).accessibilityLabel("目标金额")
                    }
                    Toggle("达成时轻轻庆祝一下", isOn: $desktop.goal.celebrate)
                    note("以今日预估收入为进度，每天零点重置。达成时间会跳过休息时段；庆祝只在应用内出现，隐藏金额时不会弹出。")
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                title("02", "下班提醒")
                Toggle("在下班前提醒我", isOn: $desktop.reminders.offWorkEnabled)
                if desktop.reminders.offWorkEnabled {
                    Picker("提前时间", selection: $desktop.reminders.leadMinutes) {
                        Text("下班时").tag(0); Text("5 分钟").tag(5); Text("10 分钟").tag(10); Text("15 分钟").tag(15); Text("30 分钟").tag(30)
                    }.pickerStyle(.segmented)
                    note("按当天实际排班提醒，临时改班和跨夜班次也会跟随调整。")
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                title("03", "发薪日的期待")
                Toggle("显示发薪日倒计时", isOn: $desktop.reminders.paydayEnabled)
                if desktop.reminders.paydayEnabled {
                    HStack {
                        Text("每月发薪日")
                        Spacer()
                        Picker("每月发薪日", selection: $desktop.reminders.paydayDay) {
                            ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
                        }.labelsHidden().frame(width: 100)
                    }
                    Toggle("发薪日当天提醒我", isOn: $desktop.reminders.paydayNotification)
                    if desktop.reminders.paydayNotification { TimeField(label: "提醒时间", minute: $desktop.reminders.paydayMinute) }
                    note("短月自动取最后一天，不自动顺延周末。这里只按你设定的日期提醒，不代表工资已经到账。")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if desktop.reminders.needsNotificationPermission {
                    Toggle("提醒时播放声音", isOn: $desktop.reminders.soundEnabled)
                    note(model.preview ? "演示模式不申请权限，也不发送通知。" : model.notificationMessage)
                    note("保存后申请系统通知权限。通知不包含工资金额。会提前安排未来 32 天的下班提醒和接下来 3 次发薪日提醒；应用运行时每天续排。")
                } else { note("系统提醒默认关闭。小目标和发薪日倒计时无需通知权限。") }
            }
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private var schedulePage: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                title("01", "按日期修改排班")
                DatePicker("排班日期", selection: $overrideDate, in: allowedDates, displayedComponents: .date)
                    .datePickerStyle(.field).environment(\.locale, Locale(identifier: "zh_CN")).accessibilityLabel("排班日期")
                    .onChange(of: overrideDate) { _ in loadOverride() }
                Picker("当日安排", selection: $overrideWorking) {
                    Text("当日上班").tag(true); Text("休息（不计薪）").tag(false)
                }.pickerStyle(.segmented).labelsHidden()
                if overrideWorking { WorkHoursEditor(hours: $overrideHours) }
                note("仅覆盖所选日期开始的班次，跨夜班按开始日期归属。手动安排优先于自动日历；休息覆盖表示不计薪。")
                if draft.isPaidHoliday(on: overrideDate) {
                    note("当前自动安排：\(ChinaCalendar.day(overrideDate)?.name ?? "法定节日") · 带薪休假。加入休息覆盖后不再计薪。")
                }
                Button("加入临时排班") { addOverride() }.buttonStyle(SoftButton(primary: true))
                if !overrideMessage.isEmpty { Text(overrideMessage).font(.system(size: 11)).foregroundColor(Theme.green).fixedSize(horizontal: false, vertical: true) }
            }
            VStack(alignment: .leading, spacing: 12) {
                title("02", "已加入的日期 · \(draft.dayOverrides.count)")
                if draft.dayOverrides.isEmpty {
                    note("还没有临时安排。调休、补班或临时改时段，都可以在上方添加。")
                }
                ForEach(draft.dayOverrides.keys.sorted(), id: \.self) { key in
                    if let value = draft.dayOverrides[key] {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(key).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                Text(value.isWorkingDay ? value.hours.label : "休息（不计薪）").font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Button("编辑") { if let date = LocalDay.date(for: key) { overrideDate = date; loadOverride() } }.buttonStyle(.borderless)
                            Button("恢复自动安排") {
                                draft.dayOverrides.removeValue(forKey: key)
                                if key == LocalDay.key(for: overrideDate) { loadOverride() }
                                overrideMessage = "\(key) 已恢复常规排班，保存后生效。"
                            }.buttonStyle(.borderless)
                        }.padding(12).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                note("添加和恢复均属于草稿，点击底部「保存设置」才会生效。排班变化会回算当月预估收入。")
            }
        }
    }

    private var allowedDates: ClosedRange<Date> {
        LocalDay.date(for: "1900-01-01")!...LocalDay.date(for: "2200-12-31")!
    }
    private var parsedDraft: SalarySettings {
        var s = draft
        s.monthlySalary = Double(salaryText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let fixed = Double(fixedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        s.fixedDays = s.basis != .fixed && (!fixed.isFinite || fixed <= 0 || fixed > 31) ? 21.75 : fixed
        return s
    }
    private var previewSnapshot: EarningsSnapshot {
        var s = parsedDraft
        if !s.monthlySalary.isFinite || s.monthlySalary <= 0 || s.monthlySalary > 100_000_000 { s.monthlySalary = 1 }
        return SalaryEngine().snapshot(at: model.now, settings: s)
    }
    private func loadOverride() {
        if let value = draft.dayOverrides[LocalDay.key(for: overrideDate)] {
            overrideWorking = value.isWorkingDay; overrideHours = value.hours
        } else {
            overrideWorking = draft.workHours(on: overrideDate) != nil
            overrideHours = draft.hours
        }
        overrideBaseline = DayOverride(isWorkingDay: overrideWorking, hours: overrideHours)
        overrideMessage = ""
    }
    private func addOverride() {
        if overrideWorking, let message = overrideHours.validationError { error = message; return }
        let key = LocalDay.key(for: overrideDate)
        var updated = parsedDraft
        updated.dayOverrides[key] = DayOverride(isWorkingDay: overrideWorking, hours: overrideHours)
        // Salary can be filled later, but conflicts and malformed schedules still need checking.
        if updated.monthlySalary <= 0 { updated.monthlySalary = 1 }
        if let message = updated.validationError { error = message; return }
        draft.dayOverrides[key] = DayOverride(isWorkingDay: overrideWorking, hours: overrideHours)
        overrideBaseline = draft.dayOverrides[key]!
        overrideMessage = "已加入 \(key)，点击底部「保存设置」生效。"
        error = ""
    }
    private func save() {
        var s = parsedDraft
        let editedOverride = DayOverride(isWorkingDay: overrideWorking, hours: overrideHours)
        if editedOverride != overrideBaseline { s.dayOverrides[LocalDay.key(for: overrideDate)] = editedOverride }
        if let message = s.validationError { error = message; return }
        var options = desktop
        options.goal.name = options.goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        options.goal.amount = Double(goalAmountText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if !options.goal.enabled && (!options.goal.amount.isFinite || options.goal.amount <= 0 || options.goal.amount > 100_000_000) { options.goal.amount = 100 }
        if let message = options.validationError { error = message; return }
        model.save(s, desktop: options)
        if !model.preview, loginEnabled != model.launchAtLogin {
            model.setLogin(loginEnabled)
            if !model.loginMessage.isEmpty { error = "偏好已保存。\(model.loginMessage)"; return }
        }
        onSave()
    }
    private func weekday(_ day: Int) -> String { [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"][day]! }
    private func title(_ index: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(index).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.green.opacity(0.7))
            Text(text).font(.system(size: 13, weight: .semibold))
        }
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
    }
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundColor(Theme.muted); Spacer(); Text(value).fontWeight(.semibold).monospacedDigit() }.font(.system(size: 11))
    }
    private func preset(_ name: String, amount: Double) -> some View {
        Button("\(name == "今天的小目标" ? "小目标" : name) ¥\(Int(amount))") {
            desktop.goal.name = name; goalAmountText = String(format: "%.2f", amount)
        }.buttonStyle(.bordered).tint(Theme.green)
    }
}

struct WorkHoursEditor: View {
    @Binding var hours: WorkHours
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                TimeField(label: "上班", minute: $hours.startMinute)
                Text("—").foregroundColor(Theme.muted)
                TimeField(label: "下班", minute: $hours.endMinute)
            }
            if hours.endMinute < hours.startMinute {
                Text("跨夜班次：下班记为次日，排班归上班当天。").font(.system(size: 11)).foregroundColor(Theme.green)
            }
            Toggle("扣除不计薪休息", isOn: $hours.breakEnabled).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
            if hours.breakEnabled {
                HStack(spacing: 18) {
                    TimeField(label: "休息开始", minute: $hours.breakStartMinute)
                    Text("—").foregroundColor(Theme.muted)
                    TimeField(label: "休息结束", minute: $hours.breakEndMinute)
                }
            }
        }
    }
}

struct TimeField: View {
    var label: String
    @Binding var minute: Int
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.muted)
            Spacer(minLength: 4)
            DatePicker(label, selection: Binding(get: {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())!
            }, set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
                .environment(\.locale, Locale(identifier: "en_GB")).frame(width: 88).accessibilityLabel(label)
        }.padding(10).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

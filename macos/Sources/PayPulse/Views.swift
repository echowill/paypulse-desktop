import SwiftUI
import AppKit
import PayPulseCore

enum Theme {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.17)
    static let muted = Color(red: 0.46, green: 0.50, blue: 0.47)
    static let green = Color(red: 0.15, green: 0.39, blue: 0.29)
    static let lime = Color(red: 0.82, green: 0.94, blue: 0.48)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let line = Color(red: 0.88, green: 0.90, blue: 0.86)
}

struct BrandMark: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(Theme.green)
            Image(systemName: "waveform.path").font(.system(size: size * 0.54, weight: .semibold)).foregroundColor(Theme.lime)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct SoftButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(primary ? Color.white : Theme.ink)
            .padding(.vertical, 11).frame(maxWidth: .infinity)
            .background(primary ? Theme.green : Color.white.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 9) {
                HStack(spacing: 9) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("薪跳").font(.system(size: 16, weight: .semibold))
                        Text("PAYPULSE").font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundColor(Theme.muted)
                    }
                    Spacer()
                }.overlay(WindowDragRegion().help("拖动此处移动窗口"))
                Button { model.togglePrivacy() } label: {
                    Image(systemName: model.settings.hideAmounts ? "eye.slash" : "eye").font(.system(size: 14)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).foregroundColor(Theme.muted)
                    .help(model.settings.hideAmounts ? "显示金额" : "隐藏面板和菜单栏金额")
                    .accessibilityLabel(model.settings.hideAmounts ? "显示金额" : "隐藏金额")
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("今日已赚").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.72))
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(model.snapshot.state == .working ? Theme.lime : Color.white.opacity(0.5)).frame(width: 5, height: 5)
                        Text(model.snapshot.state.title).font(.system(size: 10, weight: .medium))
                    }.foregroundColor(Theme.lime).padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08)).clipShape(Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("¥").font(.system(size: 23, weight: .light)).foregroundColor(Theme.lime.opacity(0.85))
                    Text(model.amount(model.snapshot.todayEarned, digits: model.settings.showFourDecimals ? 4 : 2))
                        .font(.system(size: model.settings.showFourDecimals ? 41 : 48, weight: .medium, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.45).lineLimit(1).fixedSize(horizontal: false, vertical: true).foregroundColor(Theme.lime)
                }.padding(.top, 15).padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                Text(model.snapshot.state == .working ? "+ ¥\(model.amount(model.snapshot.secondRate, digits: 4)) / 秒，时间正在变成收入" : stateMessage)
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.62))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Theme.lime).frame(width: max(0, proxy.size.width * model.snapshot.progress))
                    }
                }.frame(height: 4).padding(.top, 24)
                HStack {
                    Text("已完成 \(Int(model.snapshot.progress * 100))%")
                    Spacer()
                    Text("今日预估 ¥\(model.amount(model.snapshot.dailyTarget))")
                }.font(.system(size: 10)).foregroundColor(.white.opacity(0.60)).padding(.top, 9)
            }.padding(22)
                .background(LinearGradient(colors: [Theme.green, Color(red: 0.10, green: 0.25, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            HStack(alignment: .top, spacing: 0) {
                metric("折合时薪", "¥\(model.amount(model.snapshot.hourlyRate))", "每小时")
                Rectangle().fill(Theme.line).frame(width: 1, height: 43).padding(.horizontal, 18)
                metric(model.snapshot.nextEventLabel.isEmpty ? model.snapshot.state.title : model.snapshot.nextEventLabel, model.countdown, model.snapshot.nextEvent == nil ? "今天也有自己的节奏" : "按设定时段自动计薪")
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            VStack(spacing: 12) {
                HStack {
                    Label(model.dateLabel, systemImage: "calendar").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Spacer()
                    Text("\(SalarySettings.timeString(model.settings.startMinute)) — \(SalarySettings.timeString(model.settings.endMinute))\(model.settings.endMinute < model.settings.startMinute ? " 次日" : "")")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
                HStack {
                    Text("本月预估已赚").foregroundColor(Theme.muted)
                    Spacer()
                    Text("¥\(model.amount(model.snapshot.monthEarned))").fontWeight(.semibold).monospacedDigit()
                }.font(.system(size: 12))
                Text("按当前排班回算 · \(model.settings.basis == .calendar ? "本月 \(model.snapshot.monthWorkdays) 个排班工作日" : "固定 \(AppModel.number(model.settings.fixedDays, digits: 2)) 天/月")")
                    .font(.system(size: 9)).foregroundColor(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button { model.toggleFloating() } label: { Label(model.floatingVisible ? "收起悬浮窗" : "桌面悬浮窗", systemImage: "rectangle.on.rectangle") }.buttonStyle(SoftButton())
                Button { model.showSettings() } label: { Label("薪资与排班", systemImage: "slider.horizontal.3") }.buttonStyle(SoftButton(primary: true))
            }
            HStack {
                Label(model.preview ? "演示数据" : "仅保存在这台 Mac", systemImage: "lock.shield").font(.system(size: 9)).foregroundColor(Theme.muted)
                Spacer()
                Button("退出") { model.quit() }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Theme.muted)
            }.padding(.top, -4)
        }.padding(24).frame(width: 400).background(Theme.paper).foregroundColor(Theme.ink).preferredColorScheme(.light)
    }
    private var stateMessage: String {
        switch model.snapshot.state {
        case .onBreak: return "休息也很重要，结束后自动继续计薪"
        case .waiting: return "上班时间一到，金额就会自动增长"
        case .finished: return "今天的努力已经记下，接下来是你的时间"
        case .dayOff: return "今天没有排班，把时间留给生活"
        default: return "设置你的月薪，让每一秒都看得见"
        }
    }
    private func metric(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(hint).font(.system(size: 9)).foregroundColor(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dedicated hit region forwards the original mouse event to AppKit's native
/// window drag loop. SwiftUI's hosting content otherwise consumes background drags.
private struct WindowDragRegion: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.set()
            window?.performDrag(with: event)
            NSCursor.openHand.set()
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct FloatingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text("今日已赚").font(.system(size: 10))
                        Circle().fill(model.snapshot.state == .working ? Theme.green : Theme.muted).frame(width: 4, height: 4)
                        Text(model.snapshot.state.title).font(.system(size: 9))
                    }.foregroundColor(Theme.muted)
                    Text("¥ \(model.amount(model.snapshot.todayEarned, digits: model.settings.showFourDecimals ? 4 : 2))")
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 0)
            }.frame(maxHeight: .infinity).overlay(WindowDragRegion().help("按住此处，可自由拖动悬浮窗"))
            VStack(spacing: 12) {
                Button { model.toggleFloating() } label: { Image(systemName: "xmark").font(.system(size: 10)) }.help("收起悬浮窗")
                Button { model.showSettings() } label: { Image(systemName: "gearshape").font(.system(size: 12)) }.help("薪资与排班")
            }.buttonStyle(.plain).foregroundColor(Theme.muted)
        }.padding(18).frame(width: 310, height: 92).background(Theme.paper).foregroundColor(Theme.ink).preferredColorScheme(.light)
    }
}

struct SettingsView: View {
    // The editor owns its draft. Live clock ticks must not invalidate field editors
    // or input-method composition while the user is typing.
    let model: AppModel
    @State private var draft: SalarySettings
    @State private var salaryText: String
    @State private var fixedDaysText: String
    @State private var error = ""
    @State private var loginEnabled: Bool
    @State private var loginMessage: String
    @FocusState private var salaryFocused: Bool
    var onSave: () -> Void
    var onCancel: () -> Void

    init(model: AppModel, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        let s = model.settings
        _draft = State(initialValue: s)
        _salaryText = State(initialValue: s.monthlySalary > 0 ? String(format: "%.2f", s.monthlySalary) : "")
        _fixedDaysText = State(initialValue: String(format: "%.2f", s.fixedDays))
        _loginEnabled = State(initialValue: model.launchAtLogin)
        _loginMessage = State(initialValue: model.loginMessage)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.configured ? "让收入跟上你的节奏" : "把时间，换成看得见的收入。")
                        .font(.system(size: 21, weight: .semibold))
                    Text("设置一次，薪跳会在工作时段自动计薪。").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("01", "你的月薪")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("¥").font(.system(size: 24, weight: .light)).foregroundColor(Theme.green)
                            TextField("例如 15000", text: $salaryText).textFieldStyle(.plain)
                                .font(.system(size: 32, weight: .medium, design: .rounded)).focused($salaryFocused).accessibilityLabel("月工资")
                            Text("元 / 月").font(.system(size: 11)).foregroundColor(Theme.muted)
                        }.padding(16).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("可填税前或到手月薪，展示口径与你的输入一致。").font(.system(size: 10)).foregroundColor(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("02", "工作与休息")
                        HStack(spacing: 18) {
                            timePicker("上班", minute: $draft.startMinute)
                            Text("—").foregroundColor(Theme.muted)
                            timePicker("下班", minute: $draft.endMinute)
                        }
                        if draft.endMinute < draft.startMinute {
                            Text("跨夜班次：下班记为次日，工作日按上班当天判断。").font(.system(size: 10)).foregroundColor(Theme.green)
                        }
                        Toggle("扣除不计薪休息", isOn: $draft.breakEnabled).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                        if draft.breakEnabled {
                            HStack(spacing: 18) {
                                timePicker("开始", minute: $draft.breakStartMinute)
                                Text("—").foregroundColor(Theme.muted)
                                timePicker("结束", minute: $draft.breakEndMinute)
                            }
                        }
                        HStack(spacing: 7) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                Button {
                                    if draft.weekdays.contains(day) { draft.weekdays.remove(day) }
                                    else { draft.weekdays.insert(day) }
                                } label: {
                                    Text([1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"][day]!)
                                        .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).frame(height: 34)
                                        .foregroundColor(draft.weekdays.contains(day) ? .white : Theme.muted)
                                        .background(draft.weekdays.contains(day) ? Theme.green : Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityLabel("周\([1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"][day]!)\(draft.weekdays.contains(day) ? "，已选" : "，未选")")
                            }
                        }.help("绿色为工作日，点击切换")
                        Text("绿色为工作日 · 暂不自动识别法定节假日与调休").font(.system(size: 10)).foregroundColor(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("03", "计薪口径")
                        Picker("计薪口径", selection: $draft.basis) {
                            Text("按本月排班工时").tag(PayBasis.calendar)
                            Text("固定月计薪天数").tag(PayBasis.fixed)
                        }.pickerStyle(.segmented).labelsHidden()
                        if draft.basis == .fixed {
                            HStack {
                                Text("每月计薪天数").font(.system(size: 12))
                                Spacer()
                                TextField("21.75", text: $fixedDaysText).textFieldStyle(.roundedBorder).frame(width: 80).accessibilityLabel("每月计薪天数")
                                Text("天").font(.system(size: 12))
                            }
                        }
                        Text(draft.basis == .calendar ? "时薪 = 月薪 ÷ 本月排班工时。完整工作月的预估收入等于月薪。" : "时薪 = 月薪 ÷ 固定天数 ÷ 每日计薪时长。每月累计可能与月薪不同。")
                            .font(.system(size: 10)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text("折合时薪").font(.system(size: 11)).foregroundColor(Theme.muted)
                            Spacer()
                            Text(previewRate).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.green)
                        }.padding(12).background(Theme.green.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("今日金额显示 4 位小数", isOn: $draft.showFourDecimals)
                        Toggle("登录 Mac 时自动启动", isOn: Binding(get: { loginEnabled }, set: {
                            model.setLogin($0)
                            loginEnabled = model.launchAtLogin
                            loginMessage = model.loginMessage
                        }))
                        if !loginMessage.isEmpty { Text(loginMessage).font(.system(size: 10)).foregroundColor(Theme.muted) }
                        Text("薪资只保存在本机。修改规则会重新计算今天和本月的预估收入；这里不是考勤或实际工资单。")
                            .font(.system(size: 10)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                }.padding(.horizontal, 28).padding(.bottom, 22)
            }
            VStack(spacing: 9) {
                if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundColor(Color(red: 0.70, green: 0.20, blue: 0.16)).frame(maxWidth: .infinity, alignment: .leading) }
                HStack(spacing: 12) {
                    Button("取消") { onCancel() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                    Button(model.configured ? "保存设置" : "开始看收入增长") { save() }.buttonStyle(SoftButton(primary: true)).keyboardShortcut(.defaultAction)
                }
            }.padding(.horizontal, 28).padding(.vertical, 16).background(Theme.paper)
        }.frame(width: 540, height: 740).background(Theme.paper).foregroundColor(Theme.ink).tint(Theme.green).accentColor(Theme.green).preferredColorScheme(.light)
            .onAppear { DispatchQueue.main.async { salaryFocused = true } }
    }

    private func sectionTitle(_ n: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(n).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.green.opacity(0.7))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
    }
    private func timePicker(_ label: String, minute: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.muted)
            Spacer()
            DatePicker(label, selection: Binding(get: {
                let day = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: day)!
            }, set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field).environment(\.locale, Locale(identifier: "en_GB")).frame(width: 82).accessibilityLabel(label)
        }.padding(10).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 9))
    }
    private func parsedDraft() -> SalarySettings {
        var s = draft
        let salary = salaryText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "").trimmingCharacters(in: .whitespaces)
        s.monthlySalary = Double(salary) ?? 0
        s.fixedDays = Double(fixedDaysText.trimmingCharacters(in: .whitespaces)) ?? 0
        return s
    }
    private var previewRate: String {
        let s = parsedDraft()
        guard s.validationError == nil else { return "填写后计算" }
        return "¥ \(AppModel.number(SalaryEngine().snapshot(at: Date(), settings: s).hourlyRate)) / 小时"
    }
    private func save() {
        let s = parsedDraft()
        if let message = s.validationError { error = message; return }
        model.save(s)
        onSave()
    }
}

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
            if let progress = model.goalProgress {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(model.desktop.goal.name, systemImage: progress.reached ? "checkmark.seal.fill" : "flag")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("¥\(model.amount(model.desktop.goal.amount))").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    ProgressView(value: progress.fraction).tint(Theme.green)
                    Text(goalMessage(progress)).font(.system(size: 10)).foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(14).background(Theme.green.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.green.opacity(model.goalCelebrating ? 0.5 : 0), lineWidth: 2).allowsHitTesting(false))
                    .animation(.easeInOut(duration: 0.3), value: model.goalCelebrating)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            VStack(spacing: 12) {
                HStack {
                    Label(model.dateLabel, systemImage: "calendar").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Spacer()
                    Button("临时排班") { model.showTemporarySchedule() }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Theme.green)
                }
                Text(model.scheduleLabel).font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("本月预估已赚").foregroundColor(Theme.muted)
                    Spacer()
                    Text("¥\(model.amount(model.snapshot.monthEarned))").fontWeight(.semibold).monospacedDigit()
                }.font(.system(size: 12))
                Text("本月实际排班 \(model.snapshot.monthWorkdays) 天 · \(AppModel.number(model.snapshot.monthScheduledSeconds / 3600, digits: 1)) 小时")
                    .font(.system(size: 9)).foregroundColor(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                Text(model.settings.basis == .calendar ? "时薪按本月实际排班工时折算" : "时薪折算：\(AppModel.number(model.settings.fixedDays)) 天/月 × 常规班计薪时长")
                    .font(.system(size: 9)).foregroundColor(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                if model.desktop.reminders.paydayEnabled {
                    HStack {
                        Label(model.paydayLabel, systemImage: "calendar.badge.clock")
                        Spacer()
                        if let date = model.paydayDate { Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) }
                    }.font(.system(size: 11, weight: .medium)).foregroundColor(Theme.green)
                }
            }
            HStack(spacing: 10) {
                Button { model.toggleFloating() } label: { Label(model.floatingVisible ? "收起悬浮窗" : "桌面悬浮窗", systemImage: "rectangle.on.rectangle") }.buttonStyle(SoftButton())
                Button { model.showSettings() } label: { Label("偏好设置", systemImage: "slider.horizontal.3") }.buttonStyle(SoftButton(primary: true))
            }
            HStack {
                Label("\(model.preview ? "演示数据" : "仅保存在这台 Mac") · \(model.versionLabel)", systemImage: "lock.shield").font(.system(size: 9)).foregroundColor(Theme.muted)
                Spacer()
                Button("退出") { model.quit() }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Theme.muted)
            }.padding(.top, -4)
        }.padding(24).frame(width: 400).background(Theme.paper).foregroundColor(Theme.ink).preferredColorScheme(.light)
    }
    private func goalMessage(_ progress: DailyGoalProgress) -> String {
        if model.settings.hideAmounts { return "金额已隐藏" }
        if progress.reached { return model.goalCelebrating ? "小目标达成，今天的努力值得庆祝！" : "今日目标已达成，明天再接再厉。" }
        if let seconds = progress.remainingWorkSeconds, let date = progress.completionDate {
            return "还需计薪 \(AppModel.duration(ceil(seconds / 60) * 60)) · 预计 \(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))) 达成"
        }
        return "还差 ¥\(model.amount(progress.remainingAmount)) · 超出今日剩余排班可赚金额"
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

/// A dedicated AppKit hit region keeps drags separate from SwiftUI controls and
/// field editors. Global event coordinates also work across displays.
struct WindowDragRegion: NSViewRepresentable {
    var onDoubleClick: (() -> Void)? = nil
    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?
        private var dragStart: NSPoint?
        private var windowOrigin: NSPoint?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        private func screenPoint(_ event: NSEvent) -> NSPoint {
            if let point = event.cgEvent?.location {
                return NSPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
            }
            return window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let onDoubleClick { onDoubleClick(); return }
            dragStart = screenPoint(event)
            windowOrigin = window?.frame.origin
            NSCursor.closedHand.set()
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStart, let origin = windowOrigin else { return }
            let point = screenPoint(event)
            window?.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
        }
        override func mouseUp(with event: NSEvent) {
            if let window, !window.frameAutosaveName.isEmpty { window.saveFrame(usingName: window.frameAutosaveName) }
            NSCursor.openHand.set()
            if ProcessInfo.processInfo.arguments.contains("--preview") && ProcessInfo.processInfo.arguments.contains("--trace-drag") {
                let message = "DRAG \(String(describing: windowOrigin)) -> \(String(describing: window?.frame.origin))\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
            dragStart = nil; windowOrigin = nil
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.onDoubleClick = onDoubleClick; return view }
    func updateNSView(_ nsView: DragView, context: Context) { nsView.onDoubleClick = onDoubleClick }
}

struct FloatingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        FloatingWidget(preferences: model.desktop.floating,
                       amount: "¥ \(model.amount(model.snapshot.todayEarned, digits: model.settings.showFourDecimals ? 4 : 2))",
                       state: model.snapshot.state, countdownLabel: model.snapshot.nextEventLabel, countdown: model.countdown,
                       celebrating: model.goalCelebrating, draggable: true,
                       onClose: { model.toggleFloating() }, onSettings: { model.showSettings() })
    }
}

struct FloatingWidget: View {
    var preferences: FloatingPreferences
    var amount: String
    var state: WorkState
    var countdownLabel: String
    var countdown: String
    var celebrating = false
    var draggable = false
    var onClose: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    @Environment(\.colorScheme) private var systemScheme
    private var dark: Bool { preferences.appearance == .dark || (preferences.appearance == .system && systemScheme == .dark) }
    private var ink: Color { dark ? Color(red: 0.90, green: 0.95, blue: 0.91) : Theme.ink }
    private var muted: Color { dark ? Color(red: 0.64, green: 0.72, blue: 0.67) : Theme.muted }
    private var paper: Color { dark ? Color(red: 0.09, green: 0.15, blue: 0.12) : Theme.paper }
    private var design: Font.Design { preferences.font == .rounded ? .rounded : (preferences.font == .monospaced ? .monospaced : .default) }
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                BrandMark(size: preferences.size == .small ? 28 : (preferences.size == .large ? 42 : 36))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(celebrating ? "✓ 小目标达成" : "今日已赚").font(.system(size: 10))
                        if preferences.size != .small && !celebrating {
                            Circle().fill(state == .working ? (dark ? Theme.lime : Theme.green) : muted).frame(width: 4, height: 4)
                            Text(state.title).font(.system(size: 9))
                        }
                    }.foregroundColor(celebrating ? (dark ? Theme.lime : Theme.green) : muted)
                    Text(amount).font(.system(size: preferences.fontSize, weight: .semibold, design: design))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    if preferences.content == .amountAndCountdown {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                            Text(countdownLabel.isEmpty ? state.title : countdownLabel)
                            Text(countdown).monospacedDigit()
                        }.font(.system(size: preferences.size == .small ? 9 : 10)).foregroundColor(muted).padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
            }.frame(maxHeight: .infinity).overlay {
                if draggable { WindowDragRegion(onDoubleClick: onSettings).help("拖动小窗 · 双击打开设置") }
            }
            VStack(spacing: 12) {
                Button { onClose?() } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 18, height: 18) }.help("收起悬浮窗").accessibilityLabel("收起悬浮窗")
                Button { onSettings?() } label: { Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 18, height: 18) }.help("偏好设置").accessibilityLabel("偏好设置")
            }.buttonStyle(.plain).foregroundColor(muted).disabled(!draggable)
        }.padding(preferences.size == .small ? 14 : 18).frame(width: preferences.width, height: preferences.height)
            .background(paper.opacity(preferences.backgroundOpacity)).foregroundColor(ink)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.opacity(dark ? 0.12 : 0.05), lineWidth: 1).allowsHitTesting(false))
            .animation(.easeInOut(duration: 0.25), value: celebrating)
    }
}

import AppKit
import SwiftUI
import ServiceManagement
import PayPulseCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: SalarySettings
    @Published var snapshot = EarningsSnapshot()
    @Published var now = Date()
    @Published var floatingVisible = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginMessage = ""
    @Published var desktop: DesktopPreferences
    @Published var goalCelebrating = false
    @Published var notificationMessage = "保存设置时会请求系统通知权限。"
    var showSettings: () -> Void = {}
    var showDashboard: () -> Void = {}
    var showTemporarySchedule: () -> Void = {}
    var toggleFloating: () -> Void = {}
    var quit: () -> Void = { NSApp.terminate(nil) }
    private var timer: Timer?
    private let defaults: UserDefaults
    private let key = "salarySettings.v1"
    private let desktopKey = "desktopPreferences.v1"
    private var notifications: LocalNotifications?
    private var notificationDay = ""
    private var celebrationTracker = DailyGoalCelebrationTracker()
    var onAppearanceChanged: (() -> Void)?
    var onTick: (() -> Void)?
    let preview: Bool
    private let previewStarted = Date()

    init() {
        preview = ProcessInfo.processInfo.arguments.contains("--preview")
        defaults = preview ? UserDefaults(suiteName: "local.paypulse.preview")! : .standard
        if preview {
            var sample = SalarySettings()
            sample.monthlySalary = 18_000
            settings = sample
            var options = DesktopPreferences()
            options.goal.enabled = true; options.goal.amount = 600; options.goal.name = "今日小目标"
            options.reminders.paydayEnabled = true; options.reminders.paydayDay = 25
            options.floating.content = .amountAndCountdown
            desktop = options
        } else if let data = defaults.data(forKey: key),
                  let stored = try? JSONDecoder().decode(SalarySettings.self, from: data),
                  stored.validationError == nil {
            settings = stored
            desktop = Self.loadDesktop(defaults: defaults)
        } else {
            settings = SalarySettings()
            desktop = Self.loadDesktop(defaults: defaults)
        }
        celebrationTracker.lastCelebratedDay = preview ? nil : defaults.string(forKey: "goalCelebrationDay")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var configured: Bool { settings.validationError == nil }
    var versionLabel: String { "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")" }
    private static func loadDesktop(defaults: UserDefaults) -> DesktopPreferences {
        guard let data = defaults.data(forKey: "desktopPreferences.v1"),
              let value = try? JSONDecoder().decode(DesktopPreferences.self, from: data),
              value.validationError == nil else { return DesktopPreferences() }
        return value
    }
    func startNotifications() {
        guard !preview, Bundle.main.bundleIdentifier != nil else { return }
        notifications = LocalNotifications()
        notifications?.onStatus = { [weak self] in self?.notificationMessage = $0 }
        notifications?.onOpen = { [weak self] in self?.showDashboard() }
        refreshNotifications()
    }
    func refreshNotifications(requestPermission: Bool = false) {
        notificationDay = LocalDay.key(for: now)
        notifications?.update(settings: settings, preferences: desktop.reminders, requestPermission: requestPermission)
    }
    func refresh() {
        if preview {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 15, minute: 26, second: 18))!
            now = anchor.addingTimeInterval(Date().timeIntervalSince(previewStarted))
        } else { now = Date() }
        snapshot = SalaryEngine().snapshot(at: now, settings: settings)
        checkGoalCrossing()
        if !preview, notificationDay != LocalDay.key(for: now) { refreshNotifications() }
        onTick?()
    }

    func save(_ updated: SalarySettings, desktop updatedDesktop: DesktopPreferences? = nil) {
        let options = updatedDesktop ?? desktop
        guard updated.validationError == nil, options.validationError == nil else { return }
        let floatingChanged = options.floating != desktop.floating
        settings = updated
        desktop = options
        celebrationTracker.resetBaseline()
        goalCelebrating = false
        if !preview, let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: key) }
        if !preview, let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: desktopKey) }
        refresh()
        if floatingChanged { onAppearanceChanged?() }
        if updatedDesktop != nil { refreshNotifications(requestPermission: true) }
    }
    func togglePrivacy() {
        var updated = settings
        updated.hideAmounts.toggle()
        save(updated)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许薪跳。" : ""
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = "设置未成功，请先将薪跳移到「应用程序」后重试。"
        }
    }
    func amount(_ value: Double, digits: Int = 2) -> String {
        if settings.hideAmounts { return "••••" }
        return Self.number(value, digits: digits)
    }
    static func number(_ value: Double, digits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }
    var countdown: String {
        guard let event = snapshot.nextEvent else { return snapshot.state == .dayOff ? "好好生活" : "自由时间" }
        let seconds = max(0, Int(ceil(event.timeIntervalSince(now))))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
    var dateLabel: String { now.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month(.twoDigits).day(.twoDigits).weekday(.wide)) }
    var scheduleLabel: String { SalaryEngine().dailyScheduleLabel(at: now, settings: settings) }
    var goalProgress: DailyGoalProgress? { SalaryEngine().goalProgress(at: now, settings: settings, goal: desktop.goal, snapshot: snapshot) }
    var paydayDate: Date? {
        guard desktop.reminders.paydayEnabled else { return nil }
        return ReminderPlanner().nextPayday(after: Calendar.current.startOfDay(for: now), day: desktop.reminders.paydayDay,
                                            minute: desktop.reminders.paydayMinute)
    }
    var paydayLabel: String {
        guard let date = paydayDate else { return "" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days == 0 ? "今天是发薪日" : "距离发薪日还有 \(days) 天"
    }
    private func checkGoalCrossing() {
        let dateKey = LocalDay.key(for: now)
        guard celebrationTracker.shouldCelebrate(day: dateKey, goal: desktop.goal, earned: snapshot.todayEarned,
                                                 hidden: settings.hideAmounts) else { return }
        if !preview { defaults.set(dateKey, forKey: "goalCelebrationDay") }
        goalCelebrating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.goalCelebrating = false }
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

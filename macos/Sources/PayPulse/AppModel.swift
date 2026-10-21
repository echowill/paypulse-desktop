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
    var showSettings: () -> Void = {}
    var toggleFloating: () -> Void = {}
    var quit: () -> Void = { NSApp.terminate(nil) }
    private var timer: Timer?
    private let defaults: UserDefaults
    private let key = "salarySettings.v1"
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
        } else if let data = defaults.data(forKey: key),
                  let stored = try? JSONDecoder().decode(SalarySettings.self, from: data),
                  stored.validationError == nil {
            settings = stored
        } else {
            settings = SalarySettings()
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var configured: Bool { settings.validationError == nil }
    func refresh() {
        if preview {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 15, minute: 26, second: 18))!
            now = anchor.addingTimeInterval(Date().timeIntervalSince(previewStarted))
        } else { now = Date() }
        snapshot = SalaryEngine().snapshot(at: now, settings: settings)
        onTick?()
    }

    func save(_ updated: SalarySettings) {
        guard updated.validationError == nil else { return }
        settings = updated
        if !preview, let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: key) }
        refresh()
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
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return "\(minutes / 60)小时\(minutes % 60)分"
    }
}

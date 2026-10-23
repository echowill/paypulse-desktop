import AppKit
import UserNotifications
import PayPulseCore

@MainActor
final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var generation = 0
    private var updateTask: Task<Void, Never>?
    var onStatus: (String) -> Void = { _ in }
    var onOpen: () -> Void = {}

    override init() {
        super.init()
        center.delegate = self
    }

    func update(settings: SalarySettings, preferences: ReminderPreferences, requestPermission: Bool = false) {
        generation += 1
        let revision = generation
        let predecessor = updateTask
        updateTask = Task {
            await predecessor?.value
            guard generation == revision else { return }
            var status = await center.notificationSettings().authorizationStatus
            if preferences.needsNotificationPermission && requestPermission && status == .notDetermined {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                    status = await center.notificationSettings().authorizationStatus
                } catch {
                    guard generation == revision else { return }
                    onStatus("通知授权未完成，可再次保存设置重试。")
                    return
                }
            }
            guard generation == revision else { return }
            let pending = await center.pendingNotificationRequests()
            guard generation == revision else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("paypulse.") }.map(\.identifier))
            guard preferences.needsNotificationPermission else {
                onStatus("系统提醒已关闭；发薪日倒计时仍可独立使用。")
                return
            }
            guard status == .authorized || status == .provisional else {
                onStatus(status == .denied ? "通知未获允许，请在系统设置 → 通知 → 薪跳中开启。" : "保存设置时会请求系统通知权限。")
                return
            }
            let plans = ReminderPlanner().reminders(after: Date(), settings: settings, preferences: preferences)
            do {
                for plan in plans {
                    guard generation == revision else { return }
                    let content = UNMutableNotificationContent()
                    if plan.kind == .offWork {
                        content.title = preferences.leadMinutes == 0 ? "到下班时间了" : "还有 \(preferences.leadMinutes) 分钟下班"
                        content.body = "按你的排班提醒。收好今天的努力，留些时间给自己。"
                    } else {
                        content.title = "今天是你设定的发薪日"
                        content.body = "这是日期提醒，实际到账以你的工资发放为准。"
                    }
                    if preferences.soundEnabled { content.sound = .default }
                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.date)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                }
                guard generation == revision else { return }
                onStatus("系统通知已允许。提醒不显示工资金额；免打扰模式可能延后显示。")
            } catch {
                guard generation == revision else { return }
                onStatus("部分提醒未能安排，请重新保存设置重试。")
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in self?.onOpen() }
        completionHandler()
    }
}

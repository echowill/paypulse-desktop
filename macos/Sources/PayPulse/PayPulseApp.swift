import AppKit
import SwiftUI
import PayPulseCore

@main
enum PayPulseApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var floatingPanel: NSPanel?
    private var previewWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch should reveal the running app, rather than add a second counter.
        if !model.preview, let id = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.showDashboard = { [weak self] in self?.showDashboard() }
        model.showTemporarySchedule = { [weak self] in self?.showSettings(tab: .schedule) }
        model.toggleFloating = { [weak self] in self?.toggleFloating() }
        model.onTick = { [weak self] in self?.updateStatus() }
        model.onAppearanceChanged = { [weak self] in self?.updateFloatingAppearance() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleDashboard)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatus()
        createAppMenu()
        model.startNotifications()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh(); self?.model.refreshNotifications() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh(); self?.model.refreshNotifications() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh(); self?.model.refreshNotifications() }
        })
        if model.preview { showPreview() }
        else if !model.configured { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.configured { showDashboard() } else { showSettings() }
        return true
    }

    private func createAppMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "偏好设置…", action: #selector(settingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出薪跳", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        main.addItem(item)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "薪跳")
        button.imagePosition = .imageLeading
        button.title = model.configured ? " ¥\(model.amount(model.snapshot.todayEarned, digits: model.settings.showFourDecimals ? 4 : 2))" : " 薪跳"
        button.toolTip = model.configured ? "薪跳 · \(model.snapshot.state.title) · 点击查看收入" : "薪跳 · 点击设置月薪"
        button.setAccessibilityLabel("薪跳，\(model.snapshot.state.title)，今日已赚\(model.amount(model.snapshot.todayEarned))元")
    }

    @objc private func settingsAction() { showSettings() }
    @objc private func toggleDashboard() {
        if !model.configured { showSettings(); return }
        if NSApp.currentEvent?.type == .rightMouseUp { showSettings(); return }
        if let window = dashboardWindow, window.isVisible { window.orderOut(nil) } else { showDashboard() }
    }
    private func showDashboard() {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        model.refresh()
        let controller = NSHostingController(rootView: AnyView(DashboardView(model: model).fixedSize(horizontal: false, vertical: true)))
        let idealHeight = controller.view.fittingSize.height
        let availableHeight = max(250, screen.visibleFrame.height - 64)
        let height = min(idealHeight, availableHeight)
        if idealHeight > availableHeight {
            controller.rootView = AnyView(ScrollView {
                DashboardView(model: model).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 400, height: height))
        }
        if dashboardWindow == nil {
            let window = SettingsWindow(contentViewController: controller)
            window.title = "薪跳 · 今日收入"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.97, green: 0.97, blue: 0.94, alpha: 1)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 400, height: height))
            let restored = window.setFrameUsingName("PayPulse.Dashboard")
            window.setFrameAutosaveName("PayPulse.Dashboard")
            if !restored {
                let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
                window.setFrameOrigin(NSPoint(x: visible.maxX - window.frame.width,
                                              y: visible.maxY - window.frame.height))
            }
            dashboardWindow = window
        } else if let window = dashboardWindow {
            let top = window.frame.maxY
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 400, height: height))
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        guard let window = dashboardWindow else { return }
        let centerPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let targetScreen = NSScreen.screens.first(where: { $0.visibleFrame.contains(centerPoint) }) ?? screen
        let safeHeight = min(idealHeight, max(250, targetScreen.visibleFrame.height - 64))
        if safeHeight != height {
            if idealHeight > safeHeight {
                controller.rootView = AnyView(ScrollView {
                    DashboardView(model: model).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 400, height: safeHeight))
            } else { controller.rootView = AnyView(DashboardView(model: model).fixedSize(horizontal: false, vertical: true)) }
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: 400, height: safeHeight))
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        // A monitor may have been disconnected since the last saved position.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(window.frame) }) {
            let visible = targetScreen.visibleFrame.insetBy(dx: 12, dy: 12)
            var frame = window.frame
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showSettings(tab: SettingsTab = .salary) {
        dashboardWindow?.orderOut(nil)
        floatingPanel?.resignKey()
        if let window = settingsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let height = min(700, max(420, (NSScreen.main?.visibleFrame.height ?? 800) - 70))
        let view = SettingsView(model: model, height: height, tab: tab, onSave: { [weak self] in
            self?.settingsWindow?.close()
            self?.showDashboard()
        }, onCancel: { [weak self] in self?.settingsWindow?.close() })
        let window = SettingsWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "薪跳 · 偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 620, height: height))
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func toggleFloating() {
        if let panel = floatingPanel, panel.isVisible {
            panel.orderOut(nil)
            model.floatingVisible = false
            return
        }
        if floatingPanel == nil {
            let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: model.desktop.floating.width, height: model.desktop.floating.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: FloatingView(model: model))
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.cornerRadius = 16
            panel.contentView?.layer?.masksToBounds = true
            let name = model.preview ? "PayPulse.Preview.Floating" : "PayPulse.Floating"
            let restored = panel.setFrameUsingName(name)
            panel.setFrameAutosaveName(name)
            if !restored, let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 24, y: screen.visibleFrame.maxY - panel.frame.height - 28))
            }
            floatingPanel = panel
        }
        updateFloatingAppearance()
        floatingPanel?.orderFrontRegardless()
        model.floatingVisible = true
        dashboardWindow?.orderOut(nil)
    }

    private func updateFloatingAppearance() {
        guard let panel = floatingPanel else { return }
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: model.desktop.floating.width, height: model.desktop.floating.height))
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var frame = panel.frame
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    private func showPreview() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--preview-view")
        let scene = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "dashboard"
        let heightIndex = args.firstIndex(of: "--preview-height")
        let height = heightIndex.flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil } ?? 700
        let tabs: [String: SettingsTab] = ["salary": .salary, "appearance": .appearance, "goals": .goals, "schedule": .schedule]
        if !args.contains("--export-preview"), let tab = tabs[scene] { showSettings(tab: tab); return }
        if !args.contains("--export-preview"), scene == "floating" { toggleFloating(); return }
        let root: AnyView
        if let tab = tabs[scene] {
            root = AnyView(SettingsView(model: model, height: min(900, max(420, height)), tab: tab, onSave: {}, onCancel: {}))
        } else if scene == "floating" || scene == "floating-dark" {
            var appearance = model.desktop.floating
            if scene == "floating-dark" { appearance.appearance = .dark; appearance.size = .large }
            root = AnyView(FloatingWidget(preferences: appearance, amount: "¥ \(model.amount(model.snapshot.todayEarned))",
                                          state: model.snapshot.state, countdownLabel: model.snapshot.nextEventLabel, countdown: model.countdown))
        } else {
            root = AnyView(DashboardView(model: model))
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "薪跳 · 演示"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        previewWindow = window
        if let index = args.firstIndex(of: "--export-preview"), args.indices.contains(index + 1) {
            let path = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let view = window.contentView else { return }
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

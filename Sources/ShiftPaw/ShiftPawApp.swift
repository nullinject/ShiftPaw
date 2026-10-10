import AppKit
import SwiftUI

@main
struct ShiftPawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()

    var body: some Scene {
        WindowGroup("ShiftPaw · 班次喵", id: "main") {
            DutyDashboard(
                model: model,
                updates: updates,
                desktopPetController: appDelegate.desktopPetController,
                dashboardCoordinator: appDelegate.windowCoordinator
            )
                .background(WindowAccessor { window in
                    appDelegate.windowCoordinator.attach(window, settings: model.settings) { position in
                        model.persistWindowPosition(position)
                    }
                })
                .onChange(of: model.settings) { _, settings in
                    appDelegate.windowCoordinator.apply(settings: settings)
                    updates.configureAutomaticChecks(settings.automaticallyChecksForUpdates)
                }
                .onAppear {
                    updates.configureAutomaticChecks(model.settings.automaticallyChecksForUpdates)
                    appDelegate.desktopPetController.prepare(
                        model: model,
                        dashboardCoordinator: appDelegate.windowCoordinator
                    )
                }
                .frame(minWidth: 330, idealWidth: 360, minHeight: 610, idealHeight: 680)
        }
        .defaultSize(width: 360, height: 680)
        .windowResizability(.contentSize)

        MenuBarExtra("ShiftPaw", systemImage: "pawprint.fill") {
            Button("显示值守面板") { appDelegate.windowCoordinator.show() }
            DesktopPetMenuCommands(
                controller: appDelegate.desktopPetController,
                model: model,
                dashboardCoordinator: appDelegate.windowCoordinator
            )
            Button("测试静音通知") { model.testNotification() }
            Divider()
            Button(updates.isChecking ? "正在检查更新…" : "检查更新") {
                Task { await updates.checkForUpdates() }
            }
            .disabled(updates.isChecking || updates.isDownloading)
            if let update = updates.availableUpdate {
                Button(updates.isDownloading ? "正在下载…" : "下载更新 \(update.version)") {
                    Task { await updates.downloadUpdate() }
                }
                .disabled(updates.isDownloading)
            }
            if updates.installerURL != nil {
                Button("打开更新安装包") { updates.openInstaller() }
            }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let windowCoordinator = WindowCoordinator()
    let desktopPetController = DesktopPetWindowController()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct DesktopPetMenuCommands: View {
    @ObservedObject var controller: DesktopPetWindowController
    @ObservedObject var model: AppModel
    let dashboardCoordinator: WindowCoordinator

    var body: some View {
        if model.settings.sedentary.isEnabled {
            Button("已活动，重新计时") { model.acknowledgeActivity() }
            if model.sedentaryReminder.isReminderActive {
                Button("10 分钟后提醒") { model.snoozeSedentaryReminder() }
            }
            Divider()
        }
        Button {
            controller.toggle(model: model, dashboardCoordinator: dashboardCoordinator)
        } label: {
            Label(
                controller.isVisible ? "隐藏桌面宠物" : "显示桌面宠物",
                systemImage: controller.isVisible ? "eye.slash" : "pawprint"
            )
        }
    }
}

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private var onPositionChanged: ((WindowPosition) -> Void)?
    private var positionSaveTask: Task<Void, Never>?

    func attach(_ window: NSWindow, settings: DutySettings, onPositionChanged: @escaping (WindowPosition) -> Void) {
        self.onPositionChanged = onPositionChanged
        guard self.window !== window else { return }
        self.window = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        apply(settings: settings)
    }

    func apply(settings: DutySettings) {
        guard let window else { return }
        window.level = settings.alwaysOnTop ? .floating : .normal
        if let position = settings.windowPosition, isVisible(position: position, for: window) {
            window.setFrameOrigin(NSPoint(x: position.x, y: position.y))
        }
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = window.frame.origin
        let position = WindowPosition(x: origin.x, y: origin.y)
        positionSaveTask?.cancel()
        positionSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            self?.onPositionChanged?(position)
        }
    }

    private func isVisible(position: WindowPosition, for window: NSWindow) -> Bool {
        var restoredFrame = window.frame
        restoredFrame.origin = NSPoint(x: position.x, y: position.y)
        return WindowPlacement.isUsable(
            windowFrame: restoredFrame,
            screenVisibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
    }
}

enum WindowPlacement {
    static func isUsable(windowFrame: CGRect, screenVisibleFrames: [CGRect]) -> Bool {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return false }
        let titleBarHeight = min(44, windowFrame.height)
        let titleBarFrame = CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - titleBarHeight,
            width: windowFrame.width,
            height: titleBarHeight
        )
        let requiredWidth = min(120, titleBarFrame.width)
        let requiredHeight = min(22, titleBarFrame.height)
        return screenVisibleFrames.contains { screenFrame in
            let visibleTitleBar = titleBarFrame.intersection(screenFrame)
            return !visibleTitleBar.isNull
                && visibleTitleBar.width >= requiredWidth
                && visibleTitleBar.height >= requiredHeight
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { onResolve(window) }
    }
}

import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: DutySettings
    @Published private(set) var snapshot: ScheduleSnapshot?
    @Published private(set) var now = Date()
    @Published private(set) var sedentaryReminder: SedentaryReminderState
    @Published var alertText: String?
    @Published var errorText: String?

    private let store: SettingsStore?
    private let notifications = SilentNotificationService()
    private var ticker: Task<Void, Never>?
    private var alertDismissTask: Task<Void, Never>?
    private var lastTick: Date
    private var deliveredOccurrenceIDs = Set<String>()

    init() {
        let startedAt = Date()
        do {
            let createdStore = try SettingsStore()
            store = createdStore
            var loadedSettings = createdStore.load()
            loadedSettings.launchAtLogin = LoginItemController.isEnabled
            settings = loadedSettings
            sedentaryReminder = SedentaryReminderState(settings: loadedSettings.sedentary, now: startedAt)
        } catch {
            Logger.application.error("Unable to create settings store: \(error.localizedDescription, privacy: .public)")
            settings = .default
            sedentaryReminder = SedentaryReminderState(settings: .default, now: startedAt)
            store = nil
        }
        lastTick = startedAt
        refresh()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                self?.tick()
            }
        }
        prepareNotifications()
    }

    deinit {
        ticker?.cancel()
        alertDismissTask?.cancel()
    }

    @discardableResult
    func update(_ mutate: (inout DutySettings) -> Void) -> Bool {
        var candidate = settings
        mutate(&candidate)
        do {
            let clean = try candidate.sanitized()
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            try store.save(clean)
            settings = clean
            sedentaryReminder.configure(clean.sedentary, at: Date())
            refresh()
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveUserSettings(events: [DutyEvent], alwaysOnTop: Bool, launchAtLogin: Bool, sedentary: SedentarySettings) -> Bool {
        do {
            var candidate = try settings.applying(
                events: events,
                alwaysOnTop: alwaysOnTop,
                launchAtLogin: launchAtLogin
            )
            candidate.sedentary = sedentary
            let clean = try candidate.sanitized()
            guard let store else { throw CocoaError(.fileNoSuchFile) }

            let previousLaunchAtLogin = settings.launchAtLogin
            let launchSettingChanged = launchAtLogin != previousLaunchAtLogin
            if launchSettingChanged {
                try LoginItemController.setEnabled(launchAtLogin)
            }
            do {
                try store.save(clean)
            } catch {
                if launchSettingChanged {
                    do {
                        try LoginItemController.setEnabled(previousLaunchAtLogin)
                    } catch {
                        Logger.application.error("Unable to roll back login item: \(error.localizedDescription, privacy: .public)")
                    }
                }
                throw error
            }

            settings = clean
            sedentaryReminder.configure(clean.sedentary, at: Date())
            refresh()
            return true
        } catch {
            errorText = "无法保存设置：\(error.localizedDescription)"
            return false
        }
    }

    func persistWindowPosition(_ position: WindowPosition) {
        guard settings.windowPosition != position else { return }
        update { $0.windowPosition = position }
    }

    func acknowledgeActivity() {
        sedentaryReminder.reset(at: Date())
    }

    func snoozeSedentaryReminder() {
        sedentaryReminder.snooze(at: Date())
    }

    func testNotification() {
        Task {
            do {
                guard try await notifications.requestAuthorizationIfNeeded() else {
                    errorText = "系统通知未获授权。请在系统设置中允许通知。"
                    return
                }
                let event = DutyEvent(id: .shiftStart, time: "00:00", action: "测试", label: "测试提醒", message: "静音提醒链路正常。", kind: .signIn)
                try await notifications.deliver(for: DutyOccurrence(event: event, date: Date(), cycleAnchor: Date()))
                showAlert("已发送静音测试提醒")
            } catch {
                errorText = "无法发送测试通知：\(error.localizedDescription)"
            }
        }
    }

    private func tick() {
        let current = Date()
        let sedentaryDue = sedentaryReminder.advance(at: current, previousTick: lastTick)
        let elapsed = min(max(current.timeIntervalSince(lastTick), 0), 30 * 60)
        let from = current.addingTimeInterval(-elapsed)
        lastTick = current
        now = current
        if let due = try? ScheduleEngine.occurrences(from: from, through: current, events: settings.events) {
            for occurrence in due {
                guard !deliveredOccurrenceIDs.contains(occurrence.id) else { continue }
                if deliveredOccurrenceIDs.count >= 256 {
                    deliveredOccurrenceIDs.removeAll(keepingCapacity: true)
                }
                deliveredOccurrenceIDs.insert(occurrence.id)
                showAlert("该\(occurrence.event.action)了！")
                deliverNotification(for: occurrence)
            }
        }
        refresh()
        if sedentaryDue {
            Task { [weak self] in
                guard let self else { return }
                do {
                    guard try await notifications.requestAuthorizationIfNeeded() else {
                        errorText = "系统通知未获授权。久坐提醒仍会显示在桌宠和面板中。"
                        return
                    }
                    // Ignore a reminder acknowledged or disabled while authorization was pending.
                    guard sedentaryReminder.isReminderActive else { return }
                    try await notifications.deliverSedentaryReminder(at: current)
                } catch {
                    errorText = "无法发送久坐提醒：\(error.localizedDescription)"
                }
            }
        }
    }

    private func refresh() {
        snapshot = try? ScheduleEngine.snapshot(at: now, events: settings.events)
    }

    private func showAlert(_ text: String) {
        alertText = text
        alertDismissTask?.cancel()
        alertDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            self?.alertText = nil
        }
    }

    private func prepareNotifications() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await notifications.requestAuthorizationIfNeeded()
            } catch {
                Logger.notifications.error("Unable to prepare notifications: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deliverNotification(for occurrence: DutyOccurrence) {
        Task { [weak self] in
            guard let self else { return }
            do {
                guard try await notifications.requestAuthorizationIfNeeded() else {
                    errorText = "系统通知未获授权。请在系统设置中允许通知。"
                    return
                }
                try await notifications.deliver(for: occurrence)
            } catch {
                errorText = "无法发送提醒：\(error.localizedDescription)"
            }
        }
    }
}

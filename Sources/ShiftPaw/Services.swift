import Foundation
import OSLog
import ServiceManagement
@preconcurrency import UserNotifications

struct SettingsStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) throws {
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportDirectory.appendingPathComponent("ShiftPaw", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("settings.json", isDirectory: false)
    }

    func load() -> DutySettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(DutySettings.self, from: data),
              let sanitized = try? settings.sanitized() else {
            return .default
        }
        return sanitized
    }

    func save(_ settings: DutySettings) throws {
        let data = try JSONEncoder().encode(settings.sanitized())
        try data.write(to: fileURL, options: [.atomic])
    }

}

@MainActor
enum LoginItemController {
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        @unknown default:
            false
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered,
                  SMAppService.mainApp.status != .notFound else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}

actor SilentNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async throws -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .badge])
        @unknown default:
            return false
        }
    }

    func deliver(for occurrence: DutyOccurrence) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(occurrence.event.action)提醒"
        content.body = occurrence.event.message
        content.categoryIdentifier = "ShiftPawReminder"
        // Deliberately leave `sound` unset: duty reminders must remain silent.
        let request = UNNotificationRequest(identifier: occurrence.id, content: content, trigger: nil)
        try await center.add(request)
    }
}

extension Logger {
    static let notifications = Logger(subsystem: "io.github.nullinject.shiftpaw", category: "notifications")
    static let application = Logger(subsystem: "io.github.nullinject.shiftpaw", category: "application")
}

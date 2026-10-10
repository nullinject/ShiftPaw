import Foundation

struct SedentarySettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var intervalMinutes: Int

    static let intervalRange = 15...180
    static let `default` = SedentarySettings(isEnabled: true, intervalMinutes: 60)
}

/// An in-session timer, independent of shift times. It does not infer posture.
struct SedentaryReminderState: Equatable, Sendable {
    private(set) var settings: SedentarySettings
    private(set) var nextReminderDate: Date?
    private(set) var isReminderActive = false

    init(settings: SedentarySettings, now: Date) {
        self.settings = settings
        reset(at: now)
    }

    mutating func configure(_ settings: SedentarySettings, at now: Date) {
        guard self.settings != settings else { return }
        self.settings = settings
        reset(at: now)
    }

    mutating func reset(at now: Date) {
        isReminderActive = false
        nextReminderDate = settings.isEnabled
            ? now.addingTimeInterval(TimeInterval(settings.intervalMinutes) * 60)
            : nil
    }

    mutating func snooze(at now: Date) {
        guard settings.isEnabled, isReminderActive else { return }
        isReminderActive = false
        nextReminderDate = now.addingTimeInterval(10 * 60)
    }

    /// Returns true once per deadline. A paused ticker or backwards clock starts fresh.
    mutating func advance(at now: Date, previousTick: Date) -> Bool {
        let elapsed = now.timeIntervalSince(previousTick)
        guard elapsed >= 0, elapsed <= 30 else {
            reset(at: now)
            return false
        }
        guard let deadline = nextReminderDate, now >= deadline else { return false }
        nextReminderDate = nil
        isReminderActive = true
        return true
    }
}

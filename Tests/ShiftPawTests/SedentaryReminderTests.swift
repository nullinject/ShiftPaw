import Foundation
import Testing
import UserNotifications
@testable import ShiftPaw

struct SedentaryReminderTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    @Test("a reminder fires at its deadline once and waits for acknowledgement")
    func firesOnce() {
        var state = SedentaryReminderState(settings: .default, now: start)
        let deadline = start.addingTimeInterval(3_600)
        #expect(state.nextReminderDate == deadline)
        let didFire1 = state.advance(at: deadline.addingTimeInterval(-1), previousTick: deadline.addingTimeInterval(-2))
        #expect(!didFire1)
        let didFire2 = state.advance(at: deadline, previousTick: deadline.addingTimeInterval(-1))
        #expect(didFire2)
        #expect(state.isReminderActive)
        #expect(state.nextReminderDate == nil)
        let didFire3 = state.advance(at: deadline.addingTimeInterval(1), previousTick: deadline)
        #expect(!didFire3)
    }

    @Test("acknowledging activity starts a full interval; snoozing starts ten minutes")
    func resetsAndSnoozes() {
        var state = SedentaryReminderState(settings: .default, now: start)
        let deadline = start.addingTimeInterval(3_600)
        _ = state.advance(at: deadline, previousTick: deadline.addingTimeInterval(-1))
        state.snooze(at: deadline)
        #expect(!state.isReminderActive)
        #expect(state.nextReminderDate == deadline.addingTimeInterval(600))
        let didFire4 = state.advance(at: deadline.addingTimeInterval(600), previousTick: deadline.addingTimeInterval(599))
        #expect(didFire4)
        state.reset(at: deadline.addingTimeInterval(610))
        #expect(!state.isReminderActive)
        #expect(state.nextReminderDate == deadline.addingTimeInterval(4_210))
    }

    @Test("disabled reminders never fire, and enabling starts a fresh interval")
    func disablingAndEnabling() {
        let disabled = SedentarySettings(isEnabled: false, intervalMinutes: 30)
        var state = SedentaryReminderState(settings: disabled, now: start)
        #expect(state.nextReminderDate == nil)
        let didFire5 = state.advance(at: start.addingTimeInterval(3_600), previousTick: start.addingTimeInterval(3_599))
        #expect(!didFire5)
        state.snooze(at: start)
        #expect(state.nextReminderDate == nil)
        state.configure(SedentarySettings(isEnabled: true, intervalMinutes: 30), at: start)
        #expect(state.nextReminderDate == start.addingTimeInterval(1_800))
        let didFire6 = state.advance(at: start.addingTimeInterval(1_800), previousTick: start.addingTimeInterval(1_799))
        #expect(didFire6)
        state.configure(disabled, at: start.addingTimeInterval(1_801))
        #expect(!state.isReminderActive)
        #expect(state.nextReminderDate == nil)
    }

    @Test("only reminder setting changes reset the countdown")
    func configuring() {
        var state = SedentaryReminderState(settings: .default, now: start)
        state.configure(.default, at: start.addingTimeInterval(100))
        #expect(state.nextReminderDate == start.addingTimeInterval(3_600))
        state.configure(SedentarySettings(isEnabled: true, intervalMinutes: 15), at: start.addingTimeInterval(100))
        #expect(state.nextReminderDate == start.addingTimeInterval(1_000))
    }

    @Test("suspension and clock rollback reset rather than sending stale reminders")
    func resumesWithoutStaleReminders() {
        var state = SedentaryReminderState(settings: .default, now: start)
        let resumed = start.addingTimeInterval(10_000)
        let didFire7 = state.advance(at: resumed, previousTick: start)
        #expect(!didFire7)
        #expect(state.nextReminderDate == resumed.addingTimeInterval(3_600))
        let didFire8 = state.advance(at: start, previousTick: resumed)
        #expect(!didFire8)
        #expect(state.nextReminderDate == start.addingTimeInterval(3_600))
    }

    @Test("old settings retain the shift and window fields while adding reminder defaults")
    func migratesOldSettings() throws {
        var original = DutySettings.default
        original.events = DutySchedulePreset.day.events
        original.alwaysOnTop = false
        original.windowPosition = WindowPosition(x: 50, y: 100)
        let data = try JSONEncoder().encode(original)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "sedentary")
        let decoded = try JSONDecoder().decode(DutySettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(try decoded.sanitized() == original)
    }

    @Test("reminder settings round trip and survive shift edits")
    func roundTripsSettings() throws {
        var settings = DutySettings.default
        settings.sedentary = SedentarySettings(isEnabled: false, intervalMinutes: 45)
        let edited = try settings.applying(events: DutySchedulePreset.day.events, alwaysOnTop: false, launchAtLogin: false)
        #expect(edited.sedentary == settings.sedentary)
        let decoded = try JSONDecoder().decode(DutySettings.self, from: JSONEncoder().encode(edited))
        #expect(try decoded.sanitized() == edited)
    }

    @Test("interval validation rejects corrupt and extreme values", arguments: [0, -1, 14, 181, Int.max])
    func rejectsInvalidIntervals(minutes: Int) {
        var settings = DutySettings.default
        settings.sedentary.intervalMinutes = minutes
        #expect(throws: DutySettingsError.self) { try settings.sanitized() }
    }

    @Test("interval validation accepts both limits", arguments: [15, 60, 180])
    func acceptsValidIntervals(minutes: Int) throws {
        var settings = DutySettings.default
        settings.sedentary.intervalMinutes = minutes
        #expect(try settings.sanitized().sedentary.intervalMinutes == minutes)
    }

    @Test("stored settings migrate, save reminders atomically and reject corrupt new fields")
    func persistsAndValidatesSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShiftPawTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SettingsStore(directory: directory)
        var settings = DutySettings.default
        settings.sedentary = SedentarySettings(isEnabled: false, intervalMinutes: 30)
        settings.events = DutySchedulePreset.day.events
        try store.save(settings)
        #expect(store.load() == settings)

        let file = directory.appendingPathComponent("settings.json")
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        legacy.removeValue(forKey: "sedentary")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        var migrated = settings
        migrated.sedentary = .default
        #expect(store.load() == migrated)

        settings.sedentary.intervalMinutes = 0
        #expect(throws: DutySettingsError.self) { try store.save(settings) }
        #expect(store.load() == migrated)
        legacy["sedentary"] = ["isEnabled": true, "intervalMinutes": 0]
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        #expect(store.load() == .default)
        legacy["sedentary"] = "invalid"
        let corrupt = try JSONSerialization.data(withJSONObject: legacy)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DutySettings.self, from: corrupt) }
    }

    @Test("sedentary notifications are silent, immediate and separate from shift reminders")
    func buildsSilentNotification() {
        let request = SilentNotificationService.sedentaryRequest(at: start)
        #expect(request.content.title == "久坐提醒")
        #expect(request.content.body.contains("起来活动一下喵"))
        #expect(request.content.sound == nil)
        #expect(request.trigger == nil)
        #expect(request.content.categoryIdentifier == "ShiftPawSedentaryReminder")
        #expect(request.identifier.hasPrefix("sedentary:"))
        #expect(request.identifier != SilentNotificationService.sedentaryRequest(at: start.addingTimeInterval(600)).identifier)
    }
}

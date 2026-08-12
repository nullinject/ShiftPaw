import Foundation
import Testing
@testable import ShiftPaw

struct ScheduleEngineTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    @Test("the default cycle moves events after midnight into the next day")
    func buildsAnOvernightCycle() throws {
        let anchor = try date("2026-08-10 12:00")
        let cycle = try ScheduleEngine.cycle(anchoredOn: anchor, events: DutySettings.default.events, calendar: calendar)

        #expect(cycle.map(\.event.id) == [.shiftStart, .midnightSignOut, .midnightSignIn, .shiftEnd])
        #expect(try formatted(cycle[2].date) == "2026-08-11 00:00")
        #expect(try formatted(cycle[3].date) == "2026-08-11 01:00")
    }

    @Test("common shift presets support same-day and overnight schedules")
    func buildsCommonShiftPresets() throws {
        let anchor = try date("2026-08-10 12:00")
        let day = try ScheduleEngine.cycle(
            anchoredOn: anchor,
            events: DutySchedulePreset.day.events,
            calendar: calendar
        )
        let overnight = try ScheduleEngine.cycle(
            anchoredOn: anchor,
            events: DutySchedulePreset.overnight.events,
            calendar: calendar
        )

        #expect(day.map(\.event.id) == [.shiftStart, .shiftEnd])
        #expect(try formatted(day[0].date) == "2026-08-10 09:00")
        #expect(try formatted(day[1].date) == "2026-08-10 18:00")
        #expect(overnight.map(\.event.id) == [.shiftStart, .shiftEnd])
        #expect(try formatted(overnight[0].date) == "2026-08-10 17:00")
        #expect(try formatted(overnight[1].date) == "2026-08-11 01:00")
        #expect(DutySchedulePreset.midnightHandoff.events.map(\.id) == DutyEventID.allCases)

        var fullDayEvents = DutySchedulePreset.day.events
        fullDayEvents[1].time = fullDayEvents[0].time
        let fullDay = try ScheduleEngine.cycle(anchoredOn: anchor, events: fullDayEvents, calendar: calendar)
        #expect(try formatted(fullDay[1].date) == "2026-08-11 09:00")
    }

    @Test("the next reminder and duty state remain correct across the midnight handoff")
    func calculatesSnapshotAcrossMidnight() throws {
        let snapshot = try ScheduleEngine.snapshot(at: date("2026-08-10 23:59"), events: DutySettings.default.events, calendar: calendar)

        #expect(snapshot.next.event.id == .midnightSignIn)
        #expect(snapshot.previous.event.id == .midnightSignOut)
        #expect(snapshot.isOnDuty == false)
    }

    @Test("a scheduler tick returns only occurrences after the prior tick")
    func findsEventsInOpenClosedRange() throws {
        let due = try ScheduleEngine.occurrences(
            from: date("2026-08-10 23:57:59"),
            through: date("2026-08-11 00:00:01"),
            events: DutySettings.default.events,
            calendar: calendar
        )

        #expect(due.map(\.event.id) == [.midnightSignOut, .midnightSignIn])
    }

    @Test("settings validation discards uneditable event content and rejects invalid times")
    func sanitizesSettings() throws {
        var candidate = DutySettings.default
        candidate.events[0].time = "18:30"
        let first = candidate.events[0]
        candidate.events[0] = DutyEvent(
            id: first.id,
            time: first.time,
            action: first.action,
            label: first.label,
            message: "untrusted",
            kind: first.kind
        )
        let clean = try candidate.sanitized()
        #expect(clean.events[0].time == "18:30")
        #expect(clean.events[0].message == DutySettings.default.events[0].message)

        candidate.events[0].time = "25:00"
        #expect(throws: DutySettingsError.self) { try candidate.sanitized() }
    }

    @Test("user settings are validated and constructed as one value")
    func buildsUserSettingsAtomically() throws {
        let updated = try DutySettings.default.applying(
            times: ["18:30", "23:45", "00:15", "02:00"],
            alwaysOnTop: false,
            launchAtLogin: true
        )

        #expect(updated.events.map(\.time) == ["18:30", "23:45", "00:15", "02:00"])
        #expect(updated.alwaysOnTop == false)
        #expect(updated.launchAtLogin == true)
        #expect(throws: DutySettingsError.self) {
            try DutySettings.default.applying(times: ["18:30"], alwaysOnTop: false, launchAtLogin: true)
        }

        let daySettings = try DutySettings.default.applying(
            events: DutySchedulePreset.day.events,
            alwaysOnTop: false,
            launchAtLogin: false
        )
        #expect(daySettings.events.map(\.id) == [.shiftStart, .shiftEnd])
        #expect(daySettings.events.map(\.time) == ["09:00", "18:00"])
    }

    @Test("window restoration requires a usable portion of the title bar")
    func validatesRestoredWindowVisibility() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)

        #expect(WindowPlacement.isUsable(
            windowFrame: CGRect(x: 1_452, y: 300, width: 360, height: 580),
            screenVisibleFrames: [screen]
        ) == false)
        #expect(WindowPlacement.isUsable(
            windowFrame: CGRect(x: 1_380, y: 300, width: 360, height: 580),
            screenVisibleFrames: [screen]
        ))
        #expect(WindowPlacement.isUsable(
            windowFrame: CGRect(x: 500, y: 950, width: 360, height: 580),
            screenVisibleFrames: [screen]
        ) == false)
    }

    @Test("desktop pet placement stays reachable after display changes")
    func validatesDesktopPetPlacement() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let size = CGSize(width: 150, height: 150)

        #expect(DesktopPetPlacement.defaultOrigin(windowSize: size, screenVisibleFrame: screen) == CGPoint(x: 1_338, y: 24))
        #expect(DesktopPetPlacement.restoredFrame(
            origin: CGPoint(x: 1_400, y: 300),
            windowSize: size,
            screenVisibleFrames: [screen]
        ) != nil)
        #expect(DesktopPetPlacement.restoredFrame(
            origin: CGPoint(x: 1_490, y: 300),
            windowSize: size,
            screenVisibleFrames: [screen]
        ) == nil)
        #expect(DesktopPetPlacement.restoredFrame(
            origin: CGPoint(x: 500, y: 1_000),
            windowSize: size,
            screenVisibleFrames: [screen]
        ) == nil)
    }

    @Test("desktop pet roaming remains inside the visible desktop")
    func advancesDesktopPetRoaming() {
        let area = DesktopPetMovement.movementArea(
            windowSize: CGSize(width: 150, height: 150),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
        )
        #expect(area == CGRect(x: 12, y: 12, width: 1_338, height: 808))

        let moving = DesktopPetMovement.advance(
            from: CGPoint(x: 20, y: 20),
            toward: CGPoint(x: 120, y: 20),
            speed: 50,
            elapsed: 1,
            within: area
        )
        #expect(moving.origin == CGPoint(x: 70, y: 20))
        #expect(moving.didReachTarget == false)
        #expect(moving.isFacingRight)

        let arrived = DesktopPetMovement.advance(
            from: moving.origin,
            toward: CGPoint(x: 120, y: 20),
            speed: 50,
            elapsed: 2,
            within: area
        )
        #expect(arrived.origin == CGPoint(x: 120, y: 20))
        #expect(arrived.didReachTarget)
    }

    @Test("desktop pet asks for attention once each elapsed hour")
    func schedulesHourlyCuteness() {
        let lastPerformed = Date(timeIntervalSince1970: 10_000)
        #expect(HourlyCutenessSchedule.isDue(
            lastPerformed: lastPerformed,
            now: lastPerformed.addingTimeInterval(3_599)
        ) == false)
        #expect(HourlyCutenessSchedule.isDue(
            lastPerformed: lastPerformed,
            now: lastPerformed.addingTimeInterval(3_600)
        ))
        #expect(HourlyCutenessSchedule.restoredLastPerformed(timestamp: nil, now: lastPerformed) == lastPerformed)
        #expect(HourlyCutenessSchedule.restoredLastPerformed(
            timestamp: lastPerformed.addingTimeInterval(60).timeIntervalSince1970,
            now: lastPerformed
        ) == lastPerformed)
    }

    @Test("countdown text uses a stable digital clock width")
    func formatsCountdownText() {
        #expect(CountdownText.format(seconds: -1) == "00:00:00")
        #expect(CountdownText.format(seconds: 3_661.9) == "01:01:01")
        #expect(CountdownText.format(seconds: 36_001) == "10:00:01")
    }

    @Test("wall clock text remains stable regardless of locale preferences")
    func formatsWallClockText() throws {
        #expect(ClockText.format(date: try date("2026-08-10 23:59:07"), calendar: calendar) == "23:59:07")
    }

    private func date(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = value.count == 16 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd HH:mm:ss"
        return try #require(formatter.date(from: value))
    }

    private func formatted(_ value: Date) throws -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: value)
    }
}

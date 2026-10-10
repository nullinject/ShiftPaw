import Foundation

enum DutyEventID: String, CaseIterable, Codable, Sendable, Identifiable {
    case shiftStart
    case midnightSignOut
    case midnightSignIn
    case shiftEnd

    var id: String { rawValue }
}

enum DutyEventKind: String, Codable, Sendable {
    case signIn
    case signOut
}

struct DutyEvent: Codable, Equatable, Sendable, Identifiable {
    let id: DutyEventID
    var time: String
    let action: String
    let label: String
    let message: String
    let kind: DutyEventKind

    static func canonical(id: DutyEventID, time: String) -> DutyEvent {
        switch id {
        case .shiftStart:
            DutyEvent(id: id, time: time, action: "签到", label: "开始值守", message: "值守开始，记得签到。", kind: .signIn)
        case .midnightSignOut:
            DutyEvent(id: id, time: time, action: "签退", label: "午夜前", message: "午夜交接时间到了，记得先签退。", kind: .signOut)
        case .midnightSignIn:
            DutyEvent(id: id, time: time, action: "签到", label: "跨日接班", message: "新的一天开始了，记得重新签到。", kind: .signIn)
        case .shiftEnd:
            DutyEvent(id: id, time: time, action: "签退", label: "结束值守", message: "本轮值守结束，记得签退。", kind: .signOut)
        }
    }
}

enum DutySchedulePreset: String, CaseIterable, Sendable, Identifiable {
    case day
    case overnight
    case midnightHandoff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "白班"
        case .overnight: "夜班"
        case .midnightHandoff: "跨日交接"
        }
    }

    var detail: String {
        switch self {
        case .day: "09:00 - 18:00"
        case .overnight: "17:00 - 次日 01:00"
        case .midnightHandoff: "含午夜签退与重签"
        }
    }

    var events: [DutyEvent] {
        switch self {
        case .day:
            [
                .canonical(id: .shiftStart, time: "09:00"),
                .canonical(id: .shiftEnd, time: "18:00")
            ]
        case .overnight:
            [
                .canonical(id: .shiftStart, time: "17:00"),
                .canonical(id: .shiftEnd, time: "01:00")
            ]
        case .midnightHandoff:
            [
                .canonical(id: .shiftStart, time: "17:00"),
                .canonical(id: .midnightSignOut, time: "23:58"),
                .canonical(id: .midnightSignIn, time: "00:00"),
                .canonical(id: .shiftEnd, time: "01:00")
            ]
        }
    }
}

struct WindowPosition: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct DutySettings: Codable, Equatable, Sendable {
    var events: [DutyEvent]
    var alwaysOnTop: Bool
    var launchAtLogin: Bool
    var windowPosition: WindowPosition?
    var sedentary: SedentarySettings = .default
    var automaticallyChecksForUpdates = true

    private enum CodingKeys: String, CodingKey {
        case events, alwaysOnTop, launchAtLogin, windowPosition, sedentary, automaticallyChecksForUpdates
    }

    init(events: [DutyEvent], alwaysOnTop: Bool, launchAtLogin: Bool, windowPosition: WindowPosition?, sedentary: SedentarySettings = .default, automaticallyChecksForUpdates: Bool = true) {
        self.events = events
        self.alwaysOnTop = alwaysOnTop
        self.launchAtLogin = launchAtLogin
        self.windowPosition = windowPosition
        self.sedentary = sedentary
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        events = try values.decode([DutyEvent].self, forKey: .events)
        alwaysOnTop = try values.decode(Bool.self, forKey: .alwaysOnTop)
        launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
        windowPosition = try values.decodeIfPresent(WindowPosition.self, forKey: .windowPosition)
        // Only an absent field uses defaults; malformed new settings still fail validation.
        sedentary = values.contains(.sedentary)
            ? try values.decode(SedentarySettings.self, forKey: .sedentary)
            : .default
        automaticallyChecksForUpdates = values.contains(.automaticallyChecksForUpdates)
            ? try values.decode(Bool.self, forKey: .automaticallyChecksForUpdates)
            : true
    }

    static let `default` = DutySettings(
        events: DutySchedulePreset.midnightHandoff.events,
        alwaysOnTop: true,
        launchAtLogin: false,
        windowPosition: nil
    )

    func sanitized() throws -> DutySettings {
        let eventIDs = events.map(\.id)
        let isRegularShift = eventIDs == [.shiftStart, .shiftEnd]
        let isMidnightHandoff = eventIDs == DutyEventID.allCases
        guard isRegularShift || isMidnightHandoff else {
            throw DutySettingsError.invalidEventOrder
        }
        let sanitizedEvents = try events.map { event in
            _ = try DutyTime(event.time)
            return DutyEvent.canonical(id: event.id, time: event.time)
        }
        let validPosition = windowPosition.flatMap { abs($0.x) < 100_000 && abs($0.y) < 100_000 ? $0 : nil }
        guard SedentarySettings.intervalRange.contains(sedentary.intervalMinutes) else {
            throw DutySettingsError.invalidSedentaryInterval
        }
        return DutySettings(events: sanitizedEvents, alwaysOnTop: alwaysOnTop, launchAtLogin: launchAtLogin, windowPosition: validPosition, sedentary: sedentary, automaticallyChecksForUpdates: automaticallyChecksForUpdates)
    }

    func applying(times: [String], alwaysOnTop: Bool, launchAtLogin: Bool) throws -> DutySettings {
        guard times.count == events.count else {
            throw DutySettingsError.invalidEventCount(expected: events.count, actual: times.count)
        }
        var candidate = self
        for index in candidate.events.indices {
            candidate.events[index].time = times[index]
        }
        candidate.alwaysOnTop = alwaysOnTop
        candidate.launchAtLogin = launchAtLogin
        return try candidate.sanitized()
    }

    func applying(events: [DutyEvent], alwaysOnTop: Bool, launchAtLogin: Bool) throws -> DutySettings {
        var candidate = self
        candidate.events = events
        candidate.alwaysOnTop = alwaysOnTop
        candidate.launchAtLogin = launchAtLogin
        return try candidate.sanitized()
    }
}

enum DutySettingsError: LocalizedError, Equatable {
    case invalidTime(String)
    case invalidEventOrder
    case invalidEventCount(expected: Int, actual: Int)
    case invalidSedentaryInterval

    var errorDescription: String? {
        switch self {
        case .invalidTime(let value): "无效时间：\(value)，请使用 HH:mm。"
        case .invalidEventOrder: "提醒节点不完整或顺序错误。"
        case .invalidEventCount(let expected, let actual): "提醒节点数量错误：应为 \(expected) 个，实际为 \(actual) 个。"
        case .invalidSedentaryInterval: "久坐提醒间隔应为 15 至 180 分钟。"
        }
    }
}

struct DutyTime: Comparable, Sendable {
    let minutesSinceMidnight: Int

    init(_ value: String) throws {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            throw DutySettingsError.invalidTime(value)
        }
        minutesSinceMidnight = hour * 60 + minute
    }

    static func < (lhs: DutyTime, rhs: DutyTime) -> Bool { lhs.minutesSinceMidnight < rhs.minutesSinceMidnight }
}

struct DutyOccurrence: Equatable, Sendable, Identifiable {
    let event: DutyEvent
    let date: Date
    let cycleAnchor: Date

    var id: String { "\(Self.dateKey(cycleAnchor)):\(event.id.rawValue):\(event.time)" }

    private static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct ScheduleSnapshot: Equatable, Sendable {
    let next: DutyOccurrence
    let previous: DutyOccurrence

    var isOnDuty: Bool { previous.event.kind == .signIn }
}

enum ScheduleEngine {
    static func cycle(anchoredOn anchor: Date, events: [DutyEvent], calendar: Calendar = .current) throws -> [DutyOccurrence] {
        let timeline = try timeline(for: events)
        let day = calendar.startOfDay(for: anchor)
        return try timeline.map { item in
            guard let date = calendar.date(byAdding: .day, value: item.dayOffset, to: day),
                  let occurrence = calendar.date(bySettingHour: item.time.minutesSinceMidnight / 60, minute: item.time.minutesSinceMidnight % 60, second: 0, of: date) else {
                throw DutySettingsError.invalidTime(item.event.time)
            }
            return DutyOccurrence(event: item.event, date: occurrence, cycleAnchor: day)
        }
    }

    static func snapshot(at date: Date, events: [DutyEvent], calendar: Calendar = .current) throws -> ScheduleSnapshot {
        let all = try candidateOccurrences(around: date, events: events, calendar: calendar)
        guard let next = all.first(where: { $0.date > date }), let previous = all.last(where: { $0.date <= date }) else {
            throw DutySettingsError.invalidEventOrder
        }
        return ScheduleSnapshot(next: next, previous: previous)
    }

    static func occurrences(from: Date, through: Date, events: [DutyEvent], calendar: Calendar = .current) throws -> [DutyOccurrence] {
        guard through > from else { return [] }
        return try candidateOccurrences(around: through, events: events, calendar: calendar).filter { $0.date > from && $0.date <= through }
    }

    private static func candidateOccurrences(around date: Date, events: [DutyEvent], calendar: Calendar) throws -> [DutyOccurrence] {
        let offsets = try timeline(for: events).map(\.dayOffset)
        let earliestAnchorOffset = -(offsets.max() ?? 0) - 1
        return try (earliestAnchorOffset...2).flatMap { (offset: Int) throws -> [DutyOccurrence] in
            guard let anchor = calendar.date(byAdding: .day, value: offset, to: date) else { return [] }
            return try cycle(anchoredOn: anchor, events: events, calendar: calendar)
        }.sorted { $0.date < $1.date }
    }

    private static func timeline(for events: [DutyEvent]) throws -> [(event: DutyEvent, time: DutyTime, dayOffset: Int)] {
        var previous: DutyTime?
        var dayOffset = 0
        return try events.map { event in
            let time = try DutyTime(event.time)
            if let previous, time <= previous { dayOffset += 1 }
            previous = time
            return (event, time, dayOffset)
        }
    }
}

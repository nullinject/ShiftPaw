import AppKit
import SwiftUI

struct DutyDashboard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var desktopPetController: DesktopPetWindowController
    let dashboardCoordinator: WindowCoordinator
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            DutyPalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                DashboardHeader(
                    isAlwaysOnTop: Binding(
                        get: { model.settings.alwaysOnTop },
                        set: { value in model.update { $0.alwaysOnTop = value } }
                    ),
                    isDesktopPetVisible: desktopPetController.isVisible,
                    onToggleDesktopPet: {
                        desktopPetController.toggle(
                            model: model,
                            dashboardCoordinator: dashboardCoordinator
                        )
                    },
                    onOpenSettings: { isShowingSettings = true }
                )

                Divider().overlay(DutyPalette.separator)

                VStack(spacing: 16) {
                    if let snapshot = model.snapshot {
                        StatusPanel(snapshot: snapshot, now: model.now)
                        EventTimeline(events: model.settings.events, nextID: snapshot.next.event.id)
                    } else {
                        ContentUnavailableView("无法读取排班", systemImage: "clock.badge.exclamationmark")
                            .frame(maxHeight: .infinity)
                    }

                    Spacer(minLength: 0)

                    AlertSlot(text: model.alertText)
                    DashboardFooter(
                        onHide: { NSApp.keyWindow?.orderOut(nil) },
                        onTestNotification: { model.testNotification() }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .tint(DutyPalette.accent)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: model)
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorText != nil },
            set: { if !$0 { model.errorText = nil } }
        )) {
            Button("好", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "未知错误")
        }
    }
}

private struct DashboardHeader: View {
    @Binding var isAlwaysOnTop: Bool
    let isDesktopPetVisible: Bool
    let onToggleDesktopPet: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(DutyPalette.accent.opacity(0.13))
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DutyPalette.accent)
            }
            .frame(width: 30, height: 30)

            Text("ShiftPaw · 班次喵")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DutyPalette.textPrimary)

            Spacer(minLength: 12)

            Toggle("始终置顶", isOn: $isAlwaysOnTop)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("始终置顶")

            Button(action: onToggleDesktopPet) {
                Image(systemName: isDesktopPetVisible ? "pawprint.fill" : "pawprint")
            }
            .buttonStyle(QuietIconButtonStyle())
            .help(isDesktopPetVisible ? "隐藏桌面宠物" : "显示桌面宠物")
            .accessibilityLabel(isDesktopPetVisible ? "隐藏桌面宠物" : "显示桌面宠物")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(QuietIconButtonStyle())
            .help("设置")
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

private struct StatusPanel: View {
    let snapshot: ScheduleSnapshot
    let now: Date

    var body: some View {
        let seconds = max(0, snapshot.next.date.timeIntervalSince(now))

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(snapshot.isOnDuty ? DutyPalette.accent : DutyPalette.textTertiary)
                    .frame(width: 7, height: 7)
                Text(snapshot.isOnDuty ? "值守中" : "待机")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isOnDuty ? DutyPalette.accent : DutyPalette.textSecondary)

                Spacer()

                Text(now.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(DutyPalette.textSecondary)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ClockText.format(date: now))
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DutyPalette.textPrimary)
                        .contentTransition(.numericText())
                        .accessibilityLabel(now.formatted(date: .omitted, time: .standard))

                    HStack(spacing: 7) {
                        Text("距\(snapshot.next.event.action)")
                            .foregroundStyle(DutyPalette.textSecondary)
                        Text(CountdownText.format(seconds: seconds))
                            .monospacedDigit()
                            .foregroundStyle(DutyPalette.accent)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 9)

                    Text("\(snapshot.next.event.time) · \(snapshot.next.event.label)")
                        .font(.caption)
                        .foregroundStyle(DutyPalette.textTertiary)
                        .padding(.top, 5)
                }

                Spacer(minLength: 4)

                DutyPetView(isOnDuty: snapshot.isOnDuty)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DutyPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(DutyPalette.separator, lineWidth: 1)
        }
    }
}

private struct DutyPetView: View {
    let isOnDuty: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 12)) { context in
            DutyPetArtwork(
                phase: context.date.timeIntervalSinceReferenceDate,
                isOnDuty: isOnDuty,
                isPerformingCute: false,
                isFacingRight: true,
                isMoving: false
            )
        }
        .frame(width: 108, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOnDuty ? "值守宠物正在工作" : "值守宠物正在待机")
    }
}

struct DutyPetArtwork: View {
    let phase: TimeInterval
    let isOnDuty: Bool
    let isPerformingCute: Bool
    let isFacingRight: Bool
    let isMoving: Bool

    private var isBlinking: Bool {
        phase.truncatingRemainder(dividingBy: 4.2) > 3.92
    }

    var body: some View {
        let runCycle = sin(phase * 10)
        let bob = sin(phase * 2.1) * 1.4
            + (isMoving ? abs(runCycle) * 3.5 : 0)
            + (isPerformingCute ? abs(sin(phase * 5.4)) * 7 : 0)
        let breath = 1 + sin(phase * 1.8) * 0.018 + (isPerformingCute ? sin(phase * 5.4) * 0.045 : 0)
        let tailAngle = 18 + sin(phase * (isOnDuty ? 3.4 : 1.8)) * 13
        let eyeHeight: CGFloat = isBlinking ? 1.5 : (isPerformingCute ? 9 : (isOnDuty ? 7 : 2))
        let eyeWidth: CGFloat = isPerformingCute ? 5 : (isOnDuty ? 4 : 8)

        ZStack {
            Capsule()
                .fill(DutyPalette.petBody.opacity(0.9))
                .frame(width: 38, height: 10)
                .rotationEffect(.degrees(isFacingRight ? tailAngle : 180 - tailAngle), anchor: .leading)
                .offset(x: 31, y: 18)

            RoundedRectangle(cornerRadius: 21)
                .fill(DutyPalette.petBody)
                .frame(width: 66, height: 42)
                .offset(y: 20)

            HStack(spacing: 23) {
                Capsule().fill(DutyPalette.petBody).frame(width: 14, height: 10)
                Capsule().fill(DutyPalette.petBody).frame(width: 14, height: 10)
            }
            .offset(x: isMoving ? runCycle * 4 : 0, y: 39)

            PetEar()
                .fill(DutyPalette.petBody)
                .frame(width: 22, height: 24)
                .offset(x: -19, y: -32)
            PetEar()
                .fill(DutyPalette.petBody)
                .frame(width: 22, height: 24)
                .scaleEffect(x: -1, y: 1)
                .offset(x: 19, y: -32)

            RoundedRectangle(cornerRadius: 20)
                .fill(DutyPalette.petBody)
                .frame(width: 60, height: 49)
                .offset(y: -8)

            HStack(spacing: 17) {
                Capsule().fill(DutyPalette.petFace).frame(width: eyeWidth, height: eyeHeight)
                Capsule().fill(DutyPalette.petFace).frame(width: eyeWidth, height: eyeHeight)
            }
            .offset(y: -12)

            Circle()
                .fill(DutyPalette.accent)
                .frame(width: 5, height: 5)
                .offset(y: -1)

            Capsule()
                .fill(DutyPalette.accent)
                .frame(width: 42, height: 5)
                .offset(y: 12)

            Image(systemName: isOnDuty ? "shield.fill" : "moon.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DutyPalette.accentForeground)
                .frame(width: 18, height: 18)
                .background(DutyPalette.accent, in: Circle())
                .offset(y: 23)

            if isPerformingCute {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DutyPalette.accent)
                    .offset(x: -31, y: -31 + sin(phase * 3) * 4)
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DutyPalette.accent)
                    .offset(x: 32, y: -25 - sin(phase * 2.4) * 5)
            }

        }
        .scaleEffect(x: isFacingRight ? 1 : -1, y: breath, anchor: .bottom)
        .offset(y: bob)
    }
}

private struct PetEar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct EventTimeline: View {
    let events: [DutyEvent]
    let nextID: DutyEventID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("值守节点")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DutyPalette.textSecondary)
                .padding(.bottom, 6)

            ForEach(events) { event in
                EventRow(event: event, isNext: event.id == nextID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventRow: View {
    let event: DutyEvent
    let isNext: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(isNext ? DutyPalette.accent : DutyPalette.separatorStrong, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                if isNext {
                    Circle()
                        .fill(DutyPalette.accent)
                        .frame(width: 6, height: 6)
                }
            }

            Text(event.time)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isNext ? DutyPalette.textPrimary : DutyPalette.textSecondary)
                .frame(width: 46, alignment: .leading)

            Text(event.label)
                .font(.system(size: 13, weight: isNext ? .semibold : .regular))
                .foregroundStyle(DutyPalette.textPrimary)

            Spacer()

            Text(event.action)
                .font(.caption)
                .foregroundStyle(isNext ? DutyPalette.accent : DutyPalette.textTertiary)
        }
        .frame(height: 39)
        .contentShape(Rectangle())
    }
}

private struct AlertSlot: View {
    let text: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge")
            Text(text ?? " ")
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(DutyPalette.accent)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .opacity(text == nil ? 0 : 1)
        .accessibilityHidden(text == nil)
    }
}

private struct DashboardFooter: View {
    let onHide: () -> Void
    let onTestNotification: () -> Void

    var body: some View {
        HStack {
            Button(action: onHide) {
                Image(systemName: "menubar.rectangle")
            }
            .buttonStyle(QuietIconButtonStyle())
            .help("隐藏到菜单栏")
            .accessibilityLabel("隐藏到菜单栏")

            Spacer()

            Button(action: onTestNotification) {
                Image(systemName: "bell.badge")
            }
            .buttonStyle(QuietIconButtonStyle())
            .help("测试静音通知")
            .accessibilityLabel("测试静音通知")
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draftEvents: [DutyEvent] = []
    @State private var alwaysOnTop = true
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("值守设置")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DutyPalette.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("关闭")
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().overlay(DutyPalette.separator)

            VStack(spacing: 16) {
                ShiftTemplateMenu(events: draftEvents) { preset in
                    draftEvents = preset.events
                }

                VStack(spacing: 0) {
                    ForEach(Array(draftEvents.enumerated()), id: \.element.id) { index, event in
                        SettingsTimeRow(event: event, time: timeBinding(for: index))
                        if index < draftEvents.count - 1 {
                            Divider()
                                .overlay(DutyPalette.separator)
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(DutyPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DutyPalette.separator, lineWidth: 1)
                }

                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "始终置顶",
                        systemImage: "pin",
                        isOn: $alwaysOnTop
                    )
                    Divider()
                        .overlay(DutyPalette.separator)
                        .padding(.leading, 42)
                    SettingsToggleRow(
                        title: "登录时启动",
                        systemImage: "power",
                        isOn: $launchAtLogin
                    )
                }
                .padding(.horizontal, 14)
                .background(DutyPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DutyPalette.separator, lineWidth: 1)
                }

                HStack {
                    Button("取消", role: .cancel) { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(DutyPalette.textSecondary)

                    Spacer()

                    Button("保存") {
                        if model.saveUserSettings(
                            events: draftEvents,
                            alwaysOnTop: alwaysOnTop,
                            launchAtLogin: launchAtLogin
                        ) {
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(width: 380)
        .background(DutyPalette.canvas)
        .tint(DutyPalette.accent)
        .onAppear {
            draftEvents = model.settings.events
            alwaysOnTop = model.settings.alwaysOnTop
            launchAtLogin = model.settings.launchAtLogin
        }
    }

    private func timeBinding(for index: Int) -> Binding<String> {
        Binding(get: { draftEvents.indices.contains(index) ? draftEvents[index].time : "" }, set: { value in
            guard draftEvents.indices.contains(index) else { return }
            draftEvents[index].time = value
        })
    }
}

private struct ShiftTemplateMenu: View {
    let events: [DutyEvent]
    let onSelect: (DutySchedulePreset) -> Void

    private var selectedPreset: DutySchedulePreset? {
        DutySchedulePreset.allCases.first { preset in
            preset.events.map(\.id) == events.map(\.id)
                && preset.events.map(\.time) == events.map(\.time)
        }
    }

    var body: some View {
        Menu {
            ForEach(DutySchedulePreset.allCases) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    if preset == selectedPreset {
                        Label("\(preset.title) · \(preset.detail)", systemImage: "checkmark")
                    } else {
                        Text("\(preset.title) · \(preset.detail)")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DutyPalette.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPreset?.title ?? "自定义班次")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DutyPalette.textPrimary)
                    Text(selectedPreset?.detail ?? "\(events.count) 个提醒节点")
                        .font(.caption)
                        .foregroundStyle(DutyPalette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DutyPalette.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .background(DutyPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DutyPalette.separator, lineWidth: 1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsTimeRow: View {
    let event: DutyEvent
    @Binding var time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind == .signIn ? "arrow.right.to.line" : "arrow.left.to.line")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DutyPalette.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DutyPalette.textPrimary)
                Text(event.action)
                    .font(.caption)
                    .foregroundStyle(DutyPalette.textTertiary)
            }

            Spacer()

            TextField("HH:mm", text: $time)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 72)
        }
        .frame(height: 52)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DutyPalette.accent)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DutyPalette.textPrimary)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .frame(height: 48)
    }
}

struct CountdownText {
    static func format(seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}

struct ClockText {
    static func format(date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}

private struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DutyPalette.textPrimary)
            .frame(width: 32, height: 30)
            .background(
                configuration.isPressed ? DutyPalette.controlPressed : DutyPalette.control,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DutyPalette.separator, lineWidth: 1)
            }
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DutyPalette.accentForeground)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(
                DutyPalette.accent.opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}

enum DutyPalette {
    static let accent = adaptive(light: 0x147D64, dark: 0x65D6B3)
    static let accentForeground = adaptive(light: 0xFFFFFF, dark: 0x10231D)
    static let canvas = adaptive(light: 0xF3F5F4, dark: 0x171A19)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x222625)
    static let control = adaptive(light: 0xF8FAF9, dark: 0x2A2F2D)
    static let controlPressed = adaptive(light: 0xE8ECEA, dark: 0x343A37)
    static let textPrimary = adaptive(light: 0x18201D, dark: 0xF2F6F4)
    static let textSecondary = adaptive(light: 0x59645F, dark: 0xAAB5B0)
    static let textTertiary = adaptive(light: 0x7D8883, dark: 0x7F8C86)
    static let separator = adaptive(light: 0xDCE2DF, dark: 0x343A37)
    static let separatorStrong = adaptive(light: 0xAEB8B3, dark: 0x68756F)
    static let petBody = adaptive(light: 0x25332E, dark: 0xD8E4DF)
    static let petFace = adaptive(light: 0xF3F5F4, dark: 0x18201D)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(from: isDark ? dark : light)
        })
    }

    private static func color(from hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
